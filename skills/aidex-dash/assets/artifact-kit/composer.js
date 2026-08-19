/* artifact-kit — the composer.
 *
 * Builds the rail (sections, then the consultation items), tracks which items
 * are answered, and composes every reply surface in an item into one markdown
 * block the reader copies in a click.
 *
 * Reply surfaces read, in this order: checked radios and checkboxes (by
 * `data-label`, falling back to `value`), selects (the selected option's text),
 * short text inputs, then textareas. An item needs at least one of them; which
 * one is the author's choice.
 *
 * Display strings are keyed off `<html lang>`, which wrap-report.sh already sets
 * from the project's `.context/artifact-style.md`. They are NOT hard-coded in
 * one language: the kit ships to every project and only the project carries a
 * language. Adding a language is one entry in STRINGS; an unknown lang falls
 * back to English rather than showing keys.
 *
 * `blank` is the identifier the artifact contract greps for in the composer
 * (comments stripped), and it is what a half-answered page is judged by. Do not
 * rename it, in any language. */
(function () {
  var STRINGS = {
    en: {
      none: 'Nothing answered yet.',
      progress: function (n, total) { return n + ' of ' + total + ' answered'; },
      missing: function (ids) { return ' · missing ' + ids.join(', '); },
      nothingToCopy: 'Nothing answered yet — there is nothing to copy.',
      copied: function (n) { return n + ' copied'; },
      blankList: function (ids) { return ' · ' + ids.length + ' blank: ' + ids.join(', '); },
      noneBlank: ' · none blank',
      paste: ' — paste them into the chat.',
      noClipboard: ' — clipboard unavailable, copy the selected text.',
      restored: function (n) { return n + ' answer(s) recovered from your last visit on this machine.'; },
      discard: 'Discard them'
    },
    es: {
      none: 'Sin responder todavía.',
      progress: function (n, total) { return n + ' de ' + total + ' respondidas'; },
      missing: function (ids) { return ' · falta ' + ids.join(', '); },
      nothingToCopy: 'Todavía no has respondido nada — no hay nada que copiar.',
      copied: function (n) { return n + ' copiada(s)'; },
      blankList: function (ids) { return ' · ' + ids.length + ' en blanco: ' + ids.join(', '); },
      noneBlank: ' · ninguna en blanco',
      paste: ' — pégalas en el chat.',
      noClipboard: ' — portapapeles no disponible, copia el texto seleccionado.',
      restored: function (n) { return n + ' respuesta(s) recuperada(s) de tu última visita en esta máquina.'; },
      discard: 'Descartarlas'
    }
  };
  var L = STRINGS[(document.documentElement.lang || 'en').slice(0, 2).toLowerCase()] || STRINGS.en;

  // Built with DOM nodes rather than innerHTML: the id and the title are author
  // text, and a title carrying an angle bracket would otherwise be parsed as
  // markup instead of shown.
  function railLink(cls, href, id, title) {
    var a = document.createElement('a');
    a.className = cls;
    a.href = href;
    var dot = document.createElement('span');
    dot.className = 'dot';
    a.appendChild(dot);
    if (id) {
      var rid = document.createElement('span');
      rid.className = 'rid';
      rid.textContent = id;
      a.appendChild(rid);
    }
    var rt = document.createElement('span');
    rt.className = 'rt';
    rt.textContent = title;
    a.appendChild(rt);
    return a;
  }

  var status = [].slice.call(document.querySelectorAll('.consult-status'));
  var buttons = [].slice.call(document.querySelectorAll('#consult-copy, #consult-copy-end'));
  var list = document.getElementById('raillist');
  var items = [].slice.call(document.querySelectorAll('.consult-item'));

  // The rail carries the sections as well as the questions: on a read with no
  // questions it is still the index, which is why it stays on every page.
  if (list) {
    document.querySelectorAll('.main > section[id]').forEach(function (sec) {
      var h = sec.querySelector('h2');
      if (!h) return;
      list.appendChild(railLink('railitem sec', '#' + sec.id, '', h.textContent));
    });
    if (items.length) {
      var sep = document.createElement('div');
      sep.className = 'railsep';
      list.appendChild(sep);
    }
  }

  var links = items.map(function (el) {
    el.id = el.dataset.id;
    if (!list) return null;
    var a = railLink('railitem', '#' + el.dataset.id, el.dataset.id, el.dataset.title || '');
    list.appendChild(a);
    return a;
  });

  function readItem(el) {
    var parts = [], marked = [];
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { marked.push(i.dataset.label || i.value || ''); });
    if (marked.length) parts.push(marked.map(function (m) { return '- ' + m; }).join('\n'));
    el.querySelectorAll('select').forEach(function (s) {
      if (s.value) parts.push(s.options[s.selectedIndex].text.trim());
    });
    el.querySelectorAll('input[type="text"]').forEach(function (i) {
      if (i.value.trim()) parts.push(i.value.trim());
    });
    el.querySelectorAll('[contenteditable]').forEach(function (c) {
      if (c.textContent.trim()) parts.push(c.textContent.trim());
    });
    el.querySelectorAll('textarea').forEach(function (t) {
      if (t.value.trim()) parts.push(t.value.trim());
    });
    return parts.join('\n\n');
  }

  function collect() {
    var answered = [], blank = [];
    items.forEach(function (el, i) {
      var body = readItem(el);
      if (links[i]) links[i].classList.toggle('done', !!body);
      if (body) answered.push('### ' + el.dataset.id + ' · ' + (el.dataset.title || '') + '\n\n' + body);
      else blank.push(el.dataset.id);
    });
    return { markdown: answered.join('\n\n'), answered: answered.length, blank: blank };
  }

  function say(text) { status.forEach(function (s) { s.textContent = text; }); }

  /* Typed answers used to live only in the open tab, so every regeneration or
   * reload discarded them — the reader lost a full answer set once and was
   * warned about the risk on every round (usage-retro run 6, R6-02). The kit
   * now keeps them in localStorage, keyed by the file's own path: local
   * artifacts share the file:// origin, so the path is what separates pages.
   *
   * Marks are stored by their data-label (the stable semantic the composer
   * already pastes), free text by surface order inside the item. Ids that left
   * the page — a decided item moved to the ledger — are dropped on the next
   * save rather than restored onto the wrong claim. Storage can be unavailable
   * (some engines refuse it on file://); every touch is wrapped, and the kit
   * degrades to exactly the old behaviour. */
  var STORE_KEY = 'aidex-kit-answers:' + location.pathname;

  function snapshotItem(el) {
    var s = { m: [], f: [] };
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { s.m.push(i.dataset.label || i.value || ''); });
    el.querySelectorAll('select').forEach(function (x) { s.f.push(x.value); });
    el.querySelectorAll('input[type="text"]').forEach(function (x) { s.f.push(x.value); });
    el.querySelectorAll('[contenteditable]').forEach(function (x) { s.f.push(x.textContent); });
    el.querySelectorAll('textarea').forEach(function (x) { s.f.push(x.value); });
    return (s.m.length || s.f.some(function (v) { return v.trim(); })) ? s : null;
  }

  function save() {
    try {
      var data = {};
      items.forEach(function (el) {
        var s = snapshotItem(el);
        if (s) data[el.dataset.id] = s;
      });
      if (Object.keys(data).length) localStorage.setItem(STORE_KEY, JSON.stringify(data));
      else localStorage.removeItem(STORE_KEY);
    } catch (e) { /* storage unavailable — the page still works, unsaved */ }
  }

  function restore() {
    var n = 0;
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (!raw) return 0;
      var data = JSON.parse(raw);
      items.forEach(function (el) {
        var s = data[el.dataset.id];
        if (!s) return;
        var hit = false;
        el.querySelectorAll('input[type="radio"], input[type="checkbox"]')
          .forEach(function (i) {
            if (s.m.indexOf(i.dataset.label || i.value || '') !== -1) { i.checked = true; hit = true; }
          });
        var free = [].slice.call(el.querySelectorAll('select'))
          .concat([].slice.call(el.querySelectorAll('input[type="text"]')))
          .concat([].slice.call(el.querySelectorAll('[contenteditable]')))
          .concat([].slice.call(el.querySelectorAll('textarea')));
        (s.f || []).forEach(function (v, i) {
          if (!free[i] || !v) return;
          if (free[i].hasAttribute('contenteditable')) free[i].textContent = v;
          else free[i].value = v;
          if (v.trim()) hit = true;
        });
        if (hit) n++;
      });
    } catch (e) { return 0; }
    return n;
  }

  function showRestoredNote(n) {
    var main = document.querySelector('.main');
    if (!main) return;
    var note = document.createElement('div');
    note.className = 'note';
    note.id = 'consult-restored';
    note.appendChild(document.createTextNode(L.restored(n) + ' '));
    var a = document.createElement('a');
    a.href = '#';
    a.textContent = L.discard;
    a.addEventListener('click', function (ev) {
      ev.preventDefault();
      try { localStorage.removeItem(STORE_KEY); } catch (e) {}
      location.reload();
    });
    note.appendChild(a);
    main.insertBefore(note, main.firstChild);
  }

  function refresh() {
    var r = collect();
    say(r.answered
      ? L.progress(r.answered, items.length) + (r.blank.length ? L.missing(r.blank) : '')
      : L.none);
  }

  function copy() {
    var r = collect();
    if (!r.answered) {
      say(L.nothingToCopy);
      return;
    }
    var msg = L.copied(r.answered) + (r.blank.length ? L.blankList(r.blank) : L.noneBlank);

    function fallback() {
      var ta = document.createElement('textarea');
      ta.value = r.markdown;
      ta.style.cssText = 'position:fixed;left:0;bottom:0;width:100%;height:9rem';
      document.body.appendChild(ta);
      ta.select();
      say(msg + L.noClipboard);
    }

    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(r.markdown)
        .then(function () { say(msg + L.paste); })
        .catch(fallback);
    } else {
      fallback();
    }
  }

  if (items.length) {
    var recovered = restore();
    if (recovered) showRestoredNote(recovered);
    document.addEventListener('input', function () { refresh(); save(); });
    document.addEventListener('change', function () { refresh(); save(); });
    refresh();
    buttons.forEach(function (b) { b.addEventListener('click', copy); });
  }
})();
