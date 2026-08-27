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
      stale: function (n) { return ' ' + n + ' were left blank because their question changed since you answered it.'; },
      consumed: function (n) { return ' ' + n + ' were left blank because you already sent them in an earlier round.'; },
      discard: 'Discard them',
      copy: 'Copy my answers',
      contents: 'Contents',
      clear: 'Clear',
      clearTitle: 'Clear this answer',
      rec: 'Recommended',
      notRec: 'Not recommended',
      recSuffix: ' (recommended)',
      notRecSuffix: ' (not recommended)'
    },
    es: {
      none: 'Sin responder todavía.',
      progress: function (n, total) { return n + ' de ' + total + ' respondidas'; },
      missing: function (ids) {
        return ' · ' + (ids.length === 1 ? 'falta ' : 'faltan ') + ids.join(', ');
      },
      nothingToCopy: 'Todavía no has respondido nada — no hay nada que copiar.',
      copied: function (n) { return n + ' copiada(s)'; },
      blankList: function (ids) { return ' · ' + ids.length + ' en blanco: ' + ids.join(', '); },
      noneBlank: ' · ninguna en blanco',
      paste: ' — pégalas en el chat.',
      noClipboard: ' — portapapeles no disponible, copia el texto seleccionado.',
      restored: function (n) { return n + ' respuesta(s) recuperada(s) de tu última visita en esta máquina.'; },
      stale: function (n) { return ' ' + n + ' se dejaron en blanco porque su pregunta cambió desde que la respondiste.'; },
      consumed: function (n) { return ' ' + n + ' se dejaron en blanco porque ya las enviaste en una ronda anterior.'; },
      discard: 'Descartarlas',
      copy: 'Copiar mis respuestas',
      contents: 'Contenido',
      clear: 'Limpiar',
      clearTitle: 'Limpiar esta respuesta',
      rec: 'Recomendada',
      notRec: 'No recomendada',
      recSuffix: ' (recomendada)',
      notRecSuffix: ' (no recomendada)'
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

  // The status line is what says "3 of 5 answered · 2 blank" — a live region,
  // or a screen reader never hears it change.
  status.forEach(function (s) { s.setAttribute('role', 'status'); });

  // The composer owns the chrome, so it speaks the page's language too. The
  // skeleton ships English defaults; only those exact defaults are replaced —
  // a label the author wrote deliberately is left alone. Without this, the
  // STRINGS table localised every status message while the buttons above them
  // stayed English, and field pages translated them by hand (or forgot to).
  buttons.forEach(function (b) {
    if (b.textContent.trim() === STRINGS.en.copy) b.textContent = L.copy;
  });
  document.querySelectorAll('.railhead').forEach(function (h) {
    if (h.textContent.trim() === STRINGS.en.contents) h.textContent = L.contents;
  });

  // The rail carries the sections as well as the questions: on a read with no
  // questions it is still the index, which is why it stays on every page.
  // A BLOCK (`section.consult-group`, BL-247) is a section whose decisions are
  // listed right under it, indented — one entry for the context, its items
  // below, never a second entry for the same context elsewhere. Items outside
  // any block (the general notes) follow after a separator.
  var links = new Array(items.length);
  function itemLink(el) {
    el.id = el.dataset.id;
    var i = items.indexOf(el);
    if (!list) return;
    var cls = el.closest('.consult-group') ? 'railitem sub' : 'railitem';
    var a = railLink(cls, '#' + el.dataset.id, el.dataset.id, el.dataset.title || '');
    list.appendChild(a);
    links[i] = a;
  }
  if (list) {
    function groupEntry(sec) {
      var h = sec.querySelector('h2, h3');
      if (!sec.id) sec.id = sec.dataset.id || '';
      list.appendChild(railLink('railitem sec grp', '#' + sec.id, '', h ? h.textContent : (sec.dataset.title || '')));
      sec.querySelectorAll('.consult-item').forEach(itemLink);
    }
    document.querySelectorAll('.main > section[id]').forEach(function (sec) {
      if (sec.classList.contains('consult-group')) return groupEntry(sec);
      var h = sec.querySelector('h2');
      if (!h) return;
      list.appendChild(railLink('railitem sec', '#' + sec.id, '', h.textContent));
      // Blocks wrapped in a container section still list under it.
      sec.querySelectorAll('.consult-group').forEach(groupEntry);
    });
    var loose = items.filter(function (el) { return !el.closest('.consult-group'); });
    if (loose.length) {
      var sep = document.createElement('div');
      sep.className = 'railsep';
      list.appendChild(sep);
    }
    loose.forEach(itemLink);
  } else {
    items.forEach(function (el) { el.id = el.dataset.id; });
  }

  /* The suffix the copied label carries, read from `data-recommended` — the
   * SAME attribute the badge is drawn from. Before this, a session with a
   * recommendation to make had no affordance and typed "(recomendada)" into
   * `data-label`, which is the string the composer pastes: the marker reached
   * the reply and never reached the page, so the reader could not see which
   * option was backed on any of ten items. One declaration, both surfaces. */
  function recSuffix(input) {
    var r = input.getAttribute('data-recommended');
    if (r === null) return '';
    return String(r).toLowerCase() === 'no' ? L.notRecSuffix : L.recSuffix;
  }

  function readItem(el) {
    var parts = [], marked = [];
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { marked.push((i.dataset.label || i.value || '') + recSuffix(i)); });
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
    var answered = [], blank = [], lastGroup = null;
    items.forEach(function (el, i) {
      var body = readItem(el);
      el.classList.toggle('has-answer', !!body);
      if (links[i]) links[i].classList.toggle('done', !!body);
      if (body) {
        /* The pasted reply keeps the block: `## G1 · title` before the first
         * answered item of each block, so the session that reads it sees the
         * grouping the reader answered under, not a flat list of ids. */
        var g = el.closest('.consult-group');
        if (g && g !== lastGroup) {
          answered.push('## ' + (g.dataset.id || g.id || '') + ' · ' + (g.dataset.title || ''));
          lastGroup = g;
        }
        answered.push('### ' + el.dataset.id + ' · ' + (el.dataset.title || '') + '\n\n' + body);
      }
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

  /* The ROUND, and what it is for.
   *
   * Persistence is for surviving a RELOAD mid-answer. It was carrying notes into
   * the next ROUND too: an item whose question did not change kept whatever the
   * reader had typed, so every regeneration handed back notes the session had
   * already read and acted on — observed with an "explain this one better"
   * request that restored into the box after the explanation had been written
   * into the page. The reader then deletes it by hand, or re-sends it.
   *
   * The discriminant is NOT the round alone. Restoring only same-round answers
   * is what the report proposed and it reverts R6-02: a regeneration would blank
   * every half-typed answer in the set, which is the loss the persistence exists
   * to prevent and which `test-composer-functional.sh` asserts against. What
   * separates the two cases is whether the answer was ever SENT — so the store
   * records that (`c`), the page records its round (`r`), and the rule is:
   *
   *   same round        -> restore everything, sent or not (the reload case)
   *   a later round     -> restore only what was never sent
   *
   * Editing an item after sending it un-sends it: `c` is derived by comparing
   * the copied fingerprint against the item's CURRENT body on every save, so no
   * extra event wiring can get out of step with it.
   *
   * No `<meta name="consult-round">` means a page written before this existed:
   * ROUND is "" and every comparison is skipped, so such a page keeps exactly
   * the v6 behaviour rather than blanking on the upgrade. */
  var roundMeta = document.querySelector('meta[name="consult-round"]');
  var ROUND = roundMeta ? (roundMeta.getAttribute('content') || '') : '';
  var copied = {};

  /* Free text is keyed by surface TYPE plus index within that type, never by
   * one global order: the v4 schema stored a single flat list, so an author
   * inserting a select before an existing textarea in the same item shifted
   * every later saved answer into the wrong box on restore. Same-type
   * insertion can still shift within its own list — that is the floor for
   * order-keyed storage — but a regeneration that adds a different control no
   * longer corrupts anything. */
  /* Keys, and why they are a fixed list rather than free choice: `m` marks,
   * `h` question fingerprint, `r` round, `x` sent, `f` the v4 flat list, plus
   * one per FREE kind below. The sent flag was first written as `c` and
   * silently WAS the contenteditable array — every such answer read as already
   * sent and vanished on the next round, which `test-composer-functional.sh`
   * caught. Adding a key means checking it against both lists. */
  var FREE = [
    { k: 's', q: 'select' },
    { k: 't', q: 'input[type="text"]' },
    { k: 'c', q: '[contenteditable]' },
    { k: 'a', q: 'textarea' }
  ];

  function freeValue(el) {
    return el.hasAttribute('contenteditable') ? el.textContent : el.value;
  }

  function setFreeValue(el, v) {
    if (el.hasAttribute('contenteditable')) el.textContent = v;
    else el.value = v;
  }

  /* A fingerprint of the QUESTION, so an answer does not restore onto a question
   * that was rephrased under it. The reported case: the reader answered, asked
   * for some questions to be explained better, and the regenerated page showed
   * those items as already answered with the old text in them. The id is
   * unchanged by design there -- the claim is the same, so `check_prev` requires
   * the id to stay, and it also refuses a changed `data-title` -- so the id
   * cannot be the discriminant. The question BODY is.
   *
   * The trigger is per item, deliberately. Clearing the store on regeneration
   * reverts R6-02: persistence exists BECAUSE "every regeneration or reload
   * discarded them -- the reader lost a full answer set once". In a set where
   * four items were handed back and nine were half-typed, that destroys the nine.
   *
   * `[contenteditable]` subtrees are blanked before hashing, and that is the one
   * thing this must get right. `setFreeValue` writes them via `.textContent`, so
   * hashing the raw text would fold the reader's own typing into the
   * fingerprint: a plain reload with no regeneration would then fail to match
   * and the answer would never come back -- R6-02 again, in the worse direction.
   * `textarea` needs no such care (`.value` does not touch child text) and
   * `<option>` text is left in on purpose: changed options invalidate the answer.
   *
   * `textContent`, never `innerHTML`: the latter fires on cosmetic markup churn
   * and would discard answers to questions that never changed.
   *
   * FNV-1a, not a crypto digest: `crypto.subtle` is async and unavailable on
   * file://, which is where these pages live. A collision restores a stale
   * answer -- exactly today's behaviour, so the failure mode is the status quo,
   * not a new one. */
  function fnv(s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = (h + (h << 1) + (h << 4) + (h << 7) + (h << 8) + (h << 24)) >>> 0;
    }
    return h.toString(16);
  }

  function questionHash(el) {
    var clone = el.cloneNode(true);
    clone.querySelectorAll('[contenteditable]').forEach(function (c) { c.textContent = ''; });
    /* Chrome this file injects — the recommendation badges and the per-item
     * clear button — is removed before hashing. Not cosmetic: it is text inside
     * the item, so leaving it in would change every fingerprint the moment the
     * kit gained these controls, and every answer stored by a reader mid-thread
     * would read as "the question changed" and be dropped on the upgrade. */
    clone.querySelectorAll('.kit-tag, .consult-clear').forEach(function (c) { c.remove(); });
    return fnv((clone.textContent || '').replace(/\s+/g, ' ').trim());
  }

  function snapshotItem(el) {
    var s = { m: [] }, any = false;
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { s.m.push(i.dataset.label || i.value || ''); });
    if (s.m.length) any = true;
    FREE.forEach(function (kind) {
      var vals = [];
      el.querySelectorAll(kind.q).forEach(function (x) { vals.push(freeValue(x)); });
      if (vals.some(function (v) { return v.trim(); })) any = true;
      if (vals.length) s[kind.k] = vals;
    });
    if (any) {
      s.h = questionHash(el);
      if (ROUND) s.r = ROUND;
      if (copied[el.dataset.id] === fnv(readItem(el))) s.x = 1;
    }
    return any ? s : null;
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
    var n = 0, stale = 0, spent = 0;
    try {
      var raw = localStorage.getItem(STORE_KEY);
      if (!raw) return { n: 0, stale: 0, spent: 0 };
      var data = JSON.parse(raw);
      items.forEach(function (el) {
        var s = data[el.dataset.id];
        if (!s) return;
        /* No `h` means an answer set saved before this existed. It is restored,
         * not discarded: upgrading the kit must not blank answers a reader
         * already typed, and the first input event re-saves the entry with a
         * fingerprint. */
        if (s.h && s.h !== questionHash(el)) { stale++; return; }
        /* Both rounds must be known before this can drop anything: an entry
         * saved before rounds existed has no `r`, and a page that predates the
         * marker has no ROUND. Either way the answer comes back, because
         * upgrading the kit must never blank what a reader already typed. */
        if (s.x && s.r && ROUND && s.r !== ROUND) { spent++; return; }
        var hit = false;
        el.querySelectorAll('input[type="radio"], input[type="checkbox"]')
          .forEach(function (i) {
            if ((s.m || []).indexOf(i.dataset.label || i.value || '') !== -1) { i.checked = true; hit = true; }
          });
        function fill(list, vals) {
          (vals || []).forEach(function (v, i) {
            if (!list[i] || !v) return;
            setFreeValue(list[i], v);
            if (v.trim()) hit = true;
          });
        }
        if (Array.isArray(s.f)) {
          // v4 schema: one flat list in fixed query order. Restored the old
          // way, so an answer set saved before the typed keying still lands.
          var free = [];
          FREE.forEach(function (kind) {
            free = free.concat([].slice.call(el.querySelectorAll(kind.q)));
          });
          fill(free, s.f);
        } else {
          FREE.forEach(function (kind) {
            fill([].slice.call(el.querySelectorAll(kind.q)), s[kind.k]);
          });
        }
        if (hit) {
          n++;
          // Restored INSIDE its own round: the answer is still a sent one, and
          // forgetting that here would make the next save record it as unsent.
          if (s.x) copied[el.dataset.id] = fnv(readItem(el));
        }
      });
    } catch (e) { return { n: 0, stale: 0, spent: 0 }; }
    return { n: n, stale: stale, spent: spent };
  }

  function showRestoredNote(n, stale, spent) {
    var main = document.querySelector('.main');
    if (!main) return;
    var note = document.createElement('div');
    note.className = 'note';
    note.id = 'consult-restored';
    note.setAttribute('role', 'status');
    note.appendChild(document.createTextNode(
      L.restored(n) + (stale ? L.stale(stale) : '')
                    + (spent ? L.consumed(spent) : '') + ' '));
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

  /* The recommendation badge. Drawn here rather than from a CSS `::after`, for
   * two reasons a stylesheet cannot cover: the word has to be in the page's own
   * language (the kit ships to every project and only the project carries one),
   * and it belongs after the option title and BEFORE its hint, which is a
   * position generated content cannot reach. */
  function markRecommendations() {
    document.querySelectorAll('.opts input[data-recommended]').forEach(function (i) {
      var lab = i.closest ? i.closest('label') : null;
      if (!lab || lab.querySelector('.kit-tag')) return;
      var no = String(i.getAttribute('data-recommended')).toLowerCase() === 'no';
      var tag = document.createElement('span');
      tag.className = 'kit-tag ' + (no ? 'no' : 'rec');
      tag.textContent = no ? L.notRec : L.rec;
      var hint = lab.querySelector('.hint');
      if (hint) hint.parentNode.insertBefore(tag, hint);
      else (lab.querySelector('span') || lab).appendChild(tag);
    });
  }

  /* Per-item clear. Radios cannot be un-selected by clicking them again and a
   * textarea has to be emptied by hand, so with persistence a wrong click
   * survived every reload and the only recovery was editing the markdown the
   * composer had already copied. Injected from here, not written into each
   * block: it is a kit affordance, so a page gets it by being wrapped rather
   * than by its author having remembered it. */
  function clearItem(el) {
    el.querySelectorAll('input[type="radio"], input[type="checkbox"]')
      .forEach(function (i) { i.checked = false; });
    FREE.forEach(function (kind) {
      el.querySelectorAll(kind.q).forEach(function (x) { setFreeValue(x, ''); });
    });
    delete copied[el.dataset.id];
    // save() rebuilds the whole store from the page, so an emptied item drops
    // out of localStorage on its own — there is no per-key delete to keep in
    // step with it.
    refresh();
    save();
  }

  function addClearControls() {
    items.forEach(function (el) {
      if (el.querySelector('.consult-clear')) return;
      var b = document.createElement('button');
      b.type = 'button';
      b.className = 'consult-clear';
      b.textContent = L.clear;
      b.title = L.clearTitle;
      b.addEventListener('click', function () { clearItem(el); });
      /* Away from the resize corner (BL-248): the control used to sit 11px
       * under the textarea's drag handle, the same size and the same corner,
       * with no confirmation. It now shares the row with the box's own label
       * — label left, Clear right — and is only shown once the item has an
       * answer (`.has-answer`, kept in step by collect()). */
      var labels = el.querySelectorAll('.fieldlabel');
      var label = labels.length ? labels[labels.length - 1] : null;
      if (label) {
        var row = document.createElement('div');
        row.className = 'fieldrow';
        label.parentNode.insertBefore(row, label);
        row.appendChild(label);
        row.appendChild(b);
      } else {
        el.appendChild(b);
      }
    });
  }

  /* Data tables (BL-248): a short cell — a number, a date, a path — never
   * wraps, so a 12-column table scrolls instead of breaking "2026-08-21" in
   * two; prose cells still wrap. `.overflows` lets the stylesheet draw the
   * right-edge fade that says "there is more" where the scrollbar is out of
   * view at the bottom of a tall table. */
  function fitTables() {
    document.querySelectorAll('.tw').forEach(function (tw) {
      tw.querySelectorAll('td').forEach(function (td) {
        if (td.textContent.trim().length <= 24) td.classList.add('nw');
      });
      var mark = function () { tw.classList.toggle('overflows', tw.scrollWidth > tw.clientWidth + 1); };
      mark();
      window.addEventListener('resize', mark);
      tw.addEventListener('scroll', function () {
        tw.classList.toggle('at-end', tw.scrollLeft + tw.clientWidth >= tw.scrollWidth - 1);
      });
    });
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
    /* Pressing the button IS sending: from here the session has the answers,
     * and the next regeneration must not hand them back. Recorded on the
     * fallback path too — there the reader copies the pre-selected text, which
     * is the same act with a worse clipboard. */
    items.forEach(function (el) {
      var body = readItem(el);
      if (body) copied[el.dataset.id] = fnv(body);
    });
    save();
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

  fitTables();
  if (items.length) {
    var recovered = restore();
    /* Shown when anything was DROPPED too, not only when something was
     * recovered: an answer the reader typed is missing from the page, and the
     * banner is the only thing that says why. */
    if (recovered.n || recovered.stale || recovered.spent) {
      showRestoredNote(recovered.n, recovered.stale, recovered.spent);
    }
    markRecommendations();
    addClearControls();
    document.addEventListener('input', function () { refresh(); save(); });
    document.addEventListener('change', function () { refresh(); save(); });
    refresh();
    buttons.forEach(function (b) { b.addEventListener('click', copy); });
  }
})();
