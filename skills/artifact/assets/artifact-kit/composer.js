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
      allDecided: 'Every question here is decided — nothing left to answer.',
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
      notes: 'Notes on this one',
      notesPh: 'Anything the options do not cover\u2026',
      listPh: 'Anything the list does not cover\u2026',
      valuePh: 'Anything the value alone does not say\u2026',
      choice: 'The choice',
      value: 'The value',
      general: 'Anything that does not fit above',
      generalPh: 'Whatever it is\u2026',
      clear: 'Clear',
      clearTitle: 'Clear this answer',
      rec: 'Recommended',
      notRec: 'Not recommended',
      recSuffix: ' (recommended)',
      notRecSuffix: ' (not recommended)',
      other: 'Other — see my notes',
      otherHint: 'None of the above; the answer is in the notes box below.',
      notNow: 'Not now \u2014 leave it for another round',
      notNowHint: 'Not a blank: the question is deferred on purpose and comes back when asked for.',
      askLabel: 'Before answering I need\u2026',
      askState: 'the state',
      askStateTitle: 'What exists today: the files by name, the value printed from the tree, what is there and what is not.',
      askOptions: 'the alternatives',
      askOptionsTitle: 'What the options are and what each one costs, the recommended one included.',
      askWhy: 'the why',
      askWhyTitle: 'The reason or the risk the item claims, with the evidence for it.',
      askSimpler: 'simpler',
      askSimplerTitle: 'The same explanation, shorter and plainer: less text, not more of it.',
      askQuestion: 'I have a question',
      askQuestionTitle: 'Something none of the above names. Write it in the notes box \u2014 ticking this puts the cursor there.',
      askReframe: 'the framing is wrong',
      askReframeTitle: 'The question itself is the wrong question. Say in the notes what it should be asking.',
      askShow: 'show me',
      askShowTitle: 'A mockup, a diagram, a before/after, worked examples \u2014 not more prose.',
      provisional: 'Provisional: you chose an option and asked for something as well. The next round answers the ask and keeps this question open, with that option already ticked.',
      toLight: 'Light',
      toDark: 'Dark',
      themeTitle: 'Switch this page between light and dark',
      decided: 'Decided',
      decidedCount: function (n) { return n + (n === 1 ? ' question already settled' : ' questions already settled'); },
      decidedHint: 'Collapsed so the open questions stay in view. Open one to re-read what it asked and what it chose.',
      zoomOpen: 'Open this tile at full size',
      zoomNative: 'Native size (1:1)',
      zoomFit: 'Fit to the window',
      zoomSizeTitle: 'Switch between fitting the window and the capture’s own pixels',
      zoomClose: 'Close',
      zoomCloseTitle: 'Close this tile and go back to the row (Esc)',
      zoomKeys: 'Left/Right: the tiles of this row · Up/Down: the same tile on the next row',
      galMode: 'Mode',
      galViewport: 'Viewport',
      galBoth: 'Both',
      galLight: 'Light',
      galDark: 'Dark',
      galDesktop: 'Desktop',
      galMobile: 'Mobile',
      galBarTitle: 'Hides tiles while you read. What you copy never changes.'
    },
    es: {
      none: 'Sin responder todavía.',
      allDecided: 'Todas las preguntas están decididas — no queda nada por responder.',
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
      notes: 'Notas sobre esta',
      notesPh: 'Cualquier cosa que las opciones no cubran\u2026',
      listPh: 'Cualquier cosa que la lista no cubra\u2026',
      valuePh: 'Cualquier cosa que el valor por s\u00ed solo no diga\u2026',
      choice: 'La elecci\u00f3n',
      value: 'El valor',
      general: 'Cualquier cosa que no encaje arriba',
      generalPh: 'Lo que sea\u2026',
      clear: 'Limpiar',
      clearTitle: 'Limpiar esta respuesta',
      rec: 'Recomendada',
      notRec: 'No recomendada',
      recSuffix: ' (recomendada)',
      notRecSuffix: ' (no recomendada)',
      other: 'Otra — lo explico en las notas',
      otherHint: 'Ninguna de las anteriores; la respuesta va en la caja de notas de abajo.',
      notNow: 'Todav\u00eda no \u2014 lo dejo para otra ronda',
      notNowHint: 'No es un blanco: la pregunta queda aplazada a prop\u00f3sito y vuelve cuando la pidas.',
      askLabel: 'Antes de responder necesito\u2026',
      askState: 'el estado',
      askStateTitle: 'Qu\u00e9 existe hoy: los archivos por nombre, el valor impreso del \u00e1rbol, qu\u00e9 hay y qu\u00e9 no.',
      askOptions: 'las alternativas',
      askOptionsTitle: 'Cu\u00e1les son las opciones y qu\u00e9 cuesta cada una, la recomendada incluida.',
      askWhy: 'el porqu\u00e9',
      askWhyTitle: 'La raz\u00f3n o el riesgo que el item afirma, con su evidencia.',
      askSimpler: 'm\u00e1s simple',
      askSimplerTitle: 'La misma explicaci\u00f3n, m\u00e1s corta y m\u00e1s llana: menos texto, no m\u00e1s.',
      askQuestion: 'tengo una pregunta',
      askQuestionTitle: 'Algo que ninguna de las anteriores nombra. Escr\u00edbela en la caja de notas \u2014 al marcar esto el cursor salta ah\u00ed.',
      askReframe: 'est\u00e1 mal planteada',
      askReframeTitle: 'La pregunta en s\u00ed est\u00e1 mal planteada. Di en las notas qu\u00e9 deber\u00eda preguntar.',
      askShow: 'mu\u00e9stramelo',
      askShowTitle: 'Un mockup, un diagrama, un antes/despu\u00e9s, ejemplos concretos \u2014 no m\u00e1s prosa.',
      provisional: 'Provisional: elegiste una opci\u00f3n y adem\u00e1s pediste algo. La pr\u00f3xima ronda responde lo que pediste y deja esta pregunta abierta, con esa opci\u00f3n ya marcada.',
      toLight: 'Claro',
      toDark: 'Oscuro',
      themeTitle: 'Cambia esta p\u00e1gina entre claro y oscuro',
      decided: 'Decidido',
      decidedCount: function (n) { return n + (n === 1 ? ' pregunta ya resuelta' : ' preguntas ya resueltas'); },
      decidedHint: 'Plegadas para que las preguntas abiertas queden a la vista. Abre una para releer qu\u00e9 preguntaba y qu\u00e9 se eligi\u00f3.',
      zoomOpen: 'Abre este tile a tama\u00f1o completo',
      zoomNative: 'Tama\u00f1o original (1:1)',
      zoomFit: 'Ajustar a la ventana',
      zoomSizeTitle: 'Alterna entre ajustar a la ventana y los p\u00edxeles propios de la captura',
      zoomClose: 'Cerrar',
      zoomCloseTitle: 'Cierra este tile y vuelve a la fila (Esc)',
      zoomKeys: 'Izquierda/Derecha: los tiles de esta fila \u00b7 Arriba/Abajo: el mismo tile en la fila siguiente',
      galMode: 'Modo',
      galViewport: 'Pantalla',
      galBoth: 'Ambos',
      galLight: 'Claro',
      galDark: 'Oscuro',
      galDesktop: 'Escritorio',
      galMobile: 'M\u00f3vil',
      galBarTitle: 'Oculta tiles mientras lees. Lo que copias no cambia.'
    }
  };
  var L = STRINGS[(document.documentElement.lang || 'en').slice(0, 2).toLowerCase()] || STRINGS.en;

  /* The strings here are NEVER translated. The `ask*` and `notNow` labels
   * above are what the reader sees; these are what the paste carries, and what
   * the session on the other side greps to know which items to rewrite and
   * WHICH WAY. Same split `recSuffix` makes between the badge and the copied
   * label, and the same rule the header gives `blank`: do not rename any of
   * them, in any language.
   *
   * By kind of gap rather than by amount (v16): a mark that only said "more"
   * left what to write to the writer, which is how an item reached 700 words
   * about the alternatives when what was missing was a table of which files
   * exist. Since v18 (BL-381) the marks combine within a round; the ceiling is
   * the ROUND — an item whose asks come back a second round is mis-shaped and
   * changes instrument or splits. */
  var EXPLAIN_STATE = '[explain-state]';
  var EXPLAIN_OPTIONS = '[explain-options]';
  /* Three more since v18 (BL-381), from 348 owner messages mined out of every
   * project transcript: the asks the reader actually typed when an item could
   * not be answered were "why is this a risk", "what IS the thing named here"
   * and "show me", none of which the two above name. And one answer-side
   * marker, `[not-now]`: a question deferred on purpose, which is not a blank.
   *
   * v19, from the census of 333 answered items (2026-09-20): `[explain-term]`
   * and its term box are RETIRED — 0 uses in 333, while "what is X" was typed
   * in prose 5 times, i.e. the reader asks in the notes and never reached for
   * the chip. Its slot goes to `[question]`, the shape that has no control at
   * all (33 of the 127 notes are a question none of the chips names): ticking
   * it focuses the notes box and the question travels there. `[reframe]` is
   * the rarest and most expensive shape (5 of 127, "creo que lo estamos
   * pensando mal") and the one every other chip assumes away. `[explain-simpler]`
   * is the only ask about the FORM of the explanation rather than a missing
   * piece of it. `[show-examples]` was proposed with them and NOT built:
   * `[show-me]` already means "a mockup, a diagram, a before/after, an example",
   * so it would have been a second control for one meaning — its title now names
   * examples explicitly instead. */
  var EXPLAIN_WHY = '[explain-why]';
  var EXPLAIN_SIMPLER = '[explain-simpler]';
  var QUESTION = '[question]';
  var REFRAME = '[reframe]';
  var SHOW_ME = '[show-me]';
  var NOT_NOW = '[not-now]';
  /* Not a chip and never ticked: a qualifier the composer appends to a chosen
   * option when an ask sits beside it. See isProvisional. */
  var PROVISIONAL = '[provisional]';

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
  // skeleton ships English defaults; only those EXACT defaults are replaced —
  // a label the author wrote deliberately is left alone. Without this, the
  // STRINGS table localised every status message while the buttons above them
  // stayed English, and field pages translated them by hand (or forgot to).
  //
  // Table-driven rather than a loop per label (BL-280): the labels and
  // placeholders an author copies out of skeleton.html are kit chrome as much
  // as the buttons are, and the promise the header makes — adding a language
  // is one STRINGS entry — only holds if no code has to be written per string.
  var CHROME = [
    ['#consult-copy, #consult-copy-end', 'text', 'copy'],
    ['.railhead', 'text', 'contents'],
    ['.fieldlabel', 'text', 'notes'],
    ['.fieldlabel', 'text', 'choice'],
    ['.fieldlabel', 'text', 'value'],
    ['.fieldlabel', 'text', 'general'],
    ['textarea', 'placeholder', 'notesPh'],
    ['textarea', 'placeholder', 'listPh'],
    ['textarea', 'placeholder', 'valuePh'],
    ['textarea', 'placeholder', 'generalPh']
  ];
  CHROME.forEach(function (row) {
    var sel = row[0], kind = row[1], key = row[2];
    document.querySelectorAll(sel).forEach(function (el) {
      if (kind === 'placeholder') {
        if ((el.getAttribute('placeholder') || '').trim() === STRINGS.en[key]) {
          el.setAttribute('placeholder', L[key]);
        }
      } else if (el.textContent.trim() === STRINGS.en[key]) {
        el.textContent = L[key];
      }
    });
  });

  /* ---- Decided items collapse out of the flow (kit v17, BL-373; in place
   * inside a half-answered block since v18, BL-380) ----------------------
   *
   * Until v16 a settled item stayed drawn where it was written. The reference
   * called that the default because the page then records the REASONING and
   * not only the outcome, and that part is right — but one live use of it
   * rejected the consequence: by round three the reader was scrolling past
   * seven answered questions to reach the open ones, on a page whose whole
   * point was that less remained each round. Reported verbatim — "es demasiado
   * distractor iterar sobre un artefacto manteniendo las mismas respuestas
   * previas... es mucho mas limpio ir iterando y tener la sensacion de que va
   * quedando menos".
   *
   * So: HIDDEN, never removed. Each decided item — or a whole block once every
   * item in it is decided, which is the unit the reader actually navigates —
   * is MOVED into one composer-built section, collapsed behind a summary that
   * carries its id, its title and the option that won. One click reopens the
   * full reasoning. The static file is untouched: the same markup an author
   * wrote still parses the same way, so `check_artifact.py` needs no change
   * and BL-359's fix keeps holding.
   *
   * It is built by the composer rather than written per page for the same
   * reason every other control is: a section hand-rolled once per round is a
   * component the kit does not define, which is the gate-1 violation BL-359
   * was itself worked around with. */
  function decidedLine(el) {
    var marked = [];
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { marked.push((i.dataset.label || i.value || '').trim()); });
    el.querySelectorAll('select').forEach(function (sel) {
      if (sel.value) marked.push(sel.options[sel.selectedIndex].text.trim());
    });
    return marked.filter(Boolean).join(' \u00b7 ');
  }

  /* A verdict written on the attribute wins over the options it chose: an item
   * whose outcome is not any single option ("both, in this order") has nowhere
   * else to say so. Bare `data-decided` keeps the derived line. */
  function decidedSummary(el) {
    var v = (el.getAttribute('data-decided') || '').trim();
    return v || decidedLine(el);
  }

  var decidedSection = null;
  function collapseDecided() {
    var decided = items.filter(isDecided);
    if (!decided.length) return;

    /* A block collapses as ONE unit only when every question in it is settled.
     * A half-answered block stays where it is, with its context intact: the
     * block is self-sufficient by contract, and hiding the context of a
     * question still being asked would break exactly that.
     *
     * Its decided SIBLINGS do not stay drawn, though (BL-380). v17 left the
     * whole block alone, and a page eleven blocks deep in its iteration looked
     * exactly like round one — "solo se ocultaban los grupos completamente
     * cerrados y no las opciones parciales". What the open question needs is
     * the block's context paragraph, not the evidence and options of a sibling
     * already settled; so each of those folds IN PLACE, behind the same
     * summary the section gives a unit, and stays where the block's order put
     * it. */
    var units = [], seen = [], inPlace = [];
    decided.forEach(function (el) {
      var g = el.closest('.consult-group');
      if (g) {
        var all = [].slice.call(g.querySelectorAll('.consult-item')).every(isDecided);
        if (all) {
          if (seen.indexOf(g) === -1) { seen.push(g); units.push({ node: g, group: true }); }
          return;
        }
        inPlace.push(el);             /* block still open — fold the item where it is */
        return;
      }
      units.push({ node: el, group: false });
    });

    function fold(u) {
      var d = document.createElement('details');
      d.className = 'decided-unit';
      var sum = document.createElement('summary');
      var k = document.createElement('span');
      k.className = 'consult-id';
      var v = document.createElement('span');
      v.className = 'decided-verdict';
      if (u.group) {
        var inner = [].slice.call(u.node.querySelectorAll('.consult-item'));
        k.textContent = u.node.dataset.id || u.node.id || '';
        v.textContent = (u.node.dataset.title || '') + ' \u2014 ' +
          inner.map(function (el) { return el.dataset.id; }).join(', ');
      } else {
        k.textContent = u.node.dataset.id || '';
        var line = decidedSummary(u.node);
        v.textContent = (u.node.dataset.title || '') + (line ? ' \u2014 ' + line : '');
      }
      sum.appendChild(k);
      sum.appendChild(v);
      d.appendChild(sum);
      return d;
    }

    inPlace.forEach(function (el) {
      var d = fold({ node: el, group: false });
      d.classList.add('inplace');
      el.parentNode.insertBefore(d, el);
      d.appendChild(el);              /* MOVED into the fold, at the same position */
    });

    if (!units.length) return;

    var sec = document.createElement('section');
    sec.id = 'sec-decided';
    sec.className = 'decided';
    var head = document.createElement('div');
    head.className = 'sec-head';
    var eyebrow = document.createElement('p');
    eyebrow.className = 'eyebrow';
    eyebrow.textContent = L.decidedCount(decided.length);
    var h2 = document.createElement('h2');
    h2.textContent = L.decided;
    head.appendChild(eyebrow);
    head.appendChild(h2);
    sec.appendChild(head);
    var hint = document.createElement('p');
    hint.className = 'decided-hint';
    hint.textContent = L.decidedHint;
    sec.appendChild(hint);

    units.forEach(function (u) {
      var d = fold(u);
      d.appendChild(u.node);          /* MOVED, not copied and not deleted */
      sec.appendChild(d);
    });

    /* After the ledger when there is one, else after the header: the reader
     * meets what is settled before what is still being asked, and the open
     * blocks keep the run of the page to themselves. */
    var after = document.getElementById('sec-ledger') ||
                document.querySelector('.main > header');
    if (after && after.parentNode) after.parentNode.insertBefore(sec, after.nextSibling);
    else (document.querySelector('.main') || document.body).appendChild(sec);
    decidedSection = sec;
  }
  collapseDecided();

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
    /* A decided item folded in place gets no entry (BL-380): its block is the
     * way in, and listing it would put the answered question back in the
     * index the reader asked to stop navigating. links[i] stays undefined,
     * which collect() already tolerates. */
    if (isDecided(el) && el.closest('.consult-group')) return;
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
      /* The collapsed section gets ONE entry and stops there. Listing what it
       * holds would put every answered question back in the index the reader
       * asked to stop navigating (BL-373); the section itself is the way in. */
      if (sec === decidedSection) return;
      // Blocks wrapped in a container section still list under it.
      sec.querySelectorAll('.consult-group').forEach(groupEntry);
    });
    var loose = items.filter(function (el) {
      return !el.closest('.consult-group') && !(decidedSection && decidedSection.contains(el));
    });
    if (loose.length) {
      var sep = document.createElement('div');
      sep.className = 'railsep';
      list.appendChild(sep);
    }
    loose.forEach(itemLink);
  } else {
    items.forEach(function (el) { el.id = el.dataset.id; });
  }

  /* Where the reader IS. The rail had a `.done` state driven by answers and
   * nothing driven by position, which is only affordable while the rail fits:
   * capping it to the viewport (BL-326) turns "the bottom half is unreachable"
   * into "the bottom half is somewhere in a box you must now also search".
   * The cap and this are one fix, not two.
   *
   * Deliberately not IntersectionObserver: the question is not "which entries
   * are visible" but "which one is the reader at", and that is the last target
   * whose top has passed the reading line — one comparison per rail entry, on
   * a list of tens. Synchronous rather than rAF-coalesced for the same reason,
   * and because a deferred frame is not guaranteed to have run when a headless
   * dump reads the DOM. */
  if (list) {
    var spy = [].slice.call(list.querySelectorAll('.railitem[href^="#"]'))
      .map(function (a) {
        return { link: a, target: document.getElementById(a.getAttribute('href').slice(1)) };
      })
      .filter(function (p) { return p.target; });
    var current = null;

    function markCurrent() {
      if (!spy.length) return;
      /* A third of the way down, not the top edge: a section whose heading has
       * just scrolled off is still the one being read. */
      var line = window.innerHeight / 3;
      var found = spy[0];
      for (var i = 0; i < spy.length; i++) {
        if (spy[i].target.getBoundingClientRect().top > line) break;
        found = spy[i];
      }
      if (found.link === current) return;
      if (current) current.removeAttribute('aria-current');
      current = found.link;
      current.setAttribute('aria-current', 'true');

      /* NOT scrollIntoView: it scrolls every scrollable ancestor, the document
       * included, so calling it from a scroll handler feeds itself. Moving the
       * list's own scrollTop touches nothing else — `scroll` does not bubble,
       * so this cannot re-enter the listener below. Rects rather than
       * offsetTop, which is relative to an offsetParent this code does not own. */
      var lr = list.getBoundingClientRect(), cr = current.getBoundingClientRect();
      var top = cr.top - lr.top + list.scrollTop;
      if (top < list.scrollTop) list.scrollTop = top;
      else if (top + cr.height > list.scrollTop + list.clientHeight) {
        list.scrollTop = top + cr.height - list.clientHeight;
      }
    }

    window.addEventListener('scroll', markCurrent, { passive: true });
    markCurrent();
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

  /* A DECIDED item (v15). The canon told an author recording a verdict to "keep
   * the items, mark the chosen option `checked`" — and that advice manufactures
   * a defect the round mechanism cannot see. `restore()` only ever marks an
   * answer as spent when it RESTORED it (`s.x` + `s.r`); an option the page
   * ships already checked was never restored, so nothing knows it was sent, and
   * it re-composes into the paste every round, forever. Reported from use, on
   * the page that carried this very decision: "me volviste a enviar las
   * primeras respuestas seleccionadas".
   *
   * So a settled decision is marked on the ITEM, not by pre-checking an input.
   * It stays visible with the option it chose and the alternatives it beat —
   * inert, because a question that is answered is not being asked — and it
   * leaves the question set entirely: no paste, no count, no injected controls.
   * Re-opening it means removing the attribute, which is a deliberate act. */
  function isDecided(el) { return el.hasAttribute('data-decided'); }

  function sealDecided() {
    items.forEach(function (el) {
      if (!isDecided(el)) return;
      el.querySelectorAll('input, select, textarea').forEach(function (i) {
        i.disabled = true;
      });
    });
  }

  /* PROVISIONAL (v19). An option chosen with an ask ticked beside it is not a
   * decision: 19 of 333 answered items are that shape and what the option MEANT
   * there was never written down — in 8 sampled rows the session held the item
   * open 7 times and once took the option as decided, so practice was already
   * "the ask wins", unwritten and drifting. The rule is now stated in the canon
   * AND carried on both surfaces: a line on the item while both are set, and a
   * `[provisional]` qualifier on the option line in the copied reply.
   *
   * `[not-now]` is not an option: deferring with an ask beside it is a deferral,
   * not a qualified answer, so it never takes the qualifier. An ask with NO
   * answer is not provisional either — there is nothing to qualify.
   *
   * THE RULE IS ABOUT AN ANSWER, NOT ABOUT AN OPTION GROUP. The kit has four
   * reply surfaces and the ask row is injected on an item whatever its surface
   * is, so a predicate that only knew `.opts` would leave a chosen SELECT value
   * or a typed VALUE with an ask beside it reading as a decision — the same
   * ambiguity, on the surfaces the option group does not cover. What is NOT an
   * answer: free prose (`textarea`, `[contenteditable]`). It is what the item's
   * notes box is for, it qualifies an answer rather than being one, and an ask
   * typed beside prose leaves the item plainly open — nothing to qualify. */
  function answerMarks(el) {
    return [].slice.call(el.querySelectorAll(
      '.opts input[type="radio"]:checked, .opts input[type="checkbox"]:checked'
    )).filter(function (i) { return (i.dataset.label || i.value || '') !== NOT_NOW; });
  }

  function answerValues(el) {
    return [].slice.call(el.querySelectorAll('select, input[type="text"]'))
      .filter(function (x) { return String(x.value || '').trim() !== ''; });
  }

  function askMarks(el) {
    return [].slice.call(el.querySelectorAll('.kit-ask input[type="checkbox"]:checked'));
  }

  function isProvisional(el) {
    if (isDecided(el)) return false;
    if (!askMarks(el).length) return false;
    return answerMarks(el).length > 0 || answerValues(el).length > 0;
  }

  /* The mark a checked input pastes. `prov` is the item's provisional state,
   * passed in rather than recomputed per input: only an ANSWER-side option
   * takes the qualifier, and it goes after the recommendation suffix so the
   * option's own text stays byte-identical to what the page shows. */
  function markLabel(i, prov) {
    var label = i.dataset.label || i.value || '';
    var qualified = prov && label !== NOT_NOW && i.closest('.opts');
    return label + recSuffix(i) + (qualified ? ' ' + PROVISIONAL : '');
  }

  function readItem(el) {
    var parts = [], marked = [], prov = isProvisional(el);
    el.querySelectorAll('input[type="radio"]:checked, input[type="checkbox"]:checked')
      .forEach(function (i) { marked.push(markLabel(i, prov)); });
    if (marked.length) parts.push(marked.map(function (m) { return '- ' + m; }).join('\n'));
    el.querySelectorAll('select').forEach(function (s) {
      if (s.value) parts.push(s.options[s.selectedIndex].text.trim() + (prov ? ' ' + PROVISIONAL : ''));
    });
    el.querySelectorAll('input[type="text"]').forEach(function (i) {
      if (i.value.trim()) parts.push(i.value.trim() + (prov ? ' ' + PROVISIONAL : ''));
    });
    el.querySelectorAll('[contenteditable]').forEach(function (c) {
      if (c.textContent.trim()) parts.push(c.textContent.trim());
    });
    el.querySelectorAll('textarea').forEach(function (t) {
      if (t.value.trim()) parts.push(t.value.trim());
    });
    return parts.join('\n\n');
  }

  /* `n` counts ITEMS. The markdown array also carries one `## G1 · title` line
   * per block, and reporting ITS length said "12 de 9" on a nine-item page —
   * every block touched was counted as an answer (BL-268). */
  function collect() {
    var answered = [], blank = [], lastGroup = null, n = 0, total = 0;
    items.forEach(function (el, i) {
      /* The general-notes item is NOT one of the questions, and counting it as
       * one made the page ask for something it never asked for: a reader who
       * answered every question still read "3 de 4 · en blanco: notes", and the
       * box that exists for what does not fit anywhere was reported as an
       * omission. It leaves the numerator, the denominator and the blank list;
       * its text still travels in the paste when it is filled. */
      if (isDecided(el)) {
        /* Shown as settled in the rail, counted nowhere, pasted never. */
        el.classList.add('has-answer');
        if (links[i]) links[i].classList.add('done');
        return;
      }
      var notes = el.classList.contains('consult-notes');
      markProvisional(el);
      var body = readItem(el);
      el.classList.toggle('has-answer', !!body);
      if (links[i]) links[i].classList.toggle('done', !!body);
      if (!notes) total++;
      if (body) {
        if (!notes) n++;
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
      else if (!notes) blank.push(el.dataset.id);
    });
    return { markdown: answered.join('\n\n'), answered: n, blank: blank,
             total: total };
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
  /* The `k` kind was the ask row's term box (v18). The box is retired with its
   * chip (v19, 0 uses in 333), so the kind is gone with it: it was last in the
   * list, so every earlier kind keeps landing where it did, and a stored `k`
   * array from a v18 page simply matches nothing on restore. */
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
    clone.querySelectorAll('.kit-tag, .consult-clear, .kit-other, .kit-notnow, .kit-ask, .kit-provisional').forEach(function (c) { c.remove(); });
    /* Chrome this file TRANSLATES is put back into English before hashing
     * (BL-280). `.fieldlabel` sits inside the item, so localising it moves the
     * fingerprint, and every answer a reader stored while the labels were still
     * English would read as "the question changed" and be dropped the moment
     * the kit gained the swap. Normalising rather than removing keeps a v10
     * page's hashes byte-identical and still lets an author's own label — never
     * equal to a translation of a default — count as part of the question. */
    CHROME.forEach(function (row) {
      if (row[1] !== 'text') return;
      clone.querySelectorAll(row[0]).forEach(function (c) {
        if (c.textContent.trim() === L[row[2]]) c.textContent = STRINGS.en[row[2]];
      });
    });
    return fnv((clone.textContent || '').replace(/\s+/g, ' ').trim());
  }

  function snapshotItem(el) {
    var s = { m: [] }, any = false;
    if (isDecided(el)) return null;
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

  /* The "other" choice, appended to every option group (BL-268). A radio set
   * is a closed list, and a reader whose answer is none of the options had two
   * bad moves: pick the nearest wrong one, or leave the group unmarked and hope
   * the notes are read as the answer. This gives the third move a mark of its
   * own — the paste then says "Other — see my notes" above the note. Injected
   * from here, in the page's language, so no author has to remember it; an
   * author who writes their own (`data-other` on an input) is left alone. It
   * takes the group's own name and input type, so a radio group stays
   * single-choice and a checkbox group stays multi. Stripped from the question
   * fingerprint, like every other injected control. */
  function addOtherChoices() {
    items.forEach(function (el) {
      if (isDecided(el)) return;
      el.querySelectorAll('.opts').forEach(function (g) {
        if (g.querySelector('.kit-other, input[data-other]')) return;
        var first = g.querySelector('input[type="radio"], input[type="checkbox"]');
        if (!first) return;
        var lab = document.createElement('label');
        lab.className = 'kit-other';
        var input = document.createElement('input');
        input.type = first.type;
        input.name = first.name;
        input.setAttribute('data-label', L.other);
        var text = document.createElement('span');
        text.appendChild(document.createTextNode(L.other + ' '));
        var hint = document.createElement('span');
        hint.className = 'hint';
        hint.textContent = L.otherHint;
        text.appendChild(hint);
        lab.appendChild(input);
        lab.appendChild(text);
        g.appendChild(lab);
        /* "Not now" (BL-381), the last choice of the group. Answer-side, so it
         * is one of the answers and exclusive with them: deferring a question
         * is not compatible with answering it, and a deferred question is not
         * a blank — "todavía, tengo muchos pendientes" three times on one page
         * left three items nagging in the count. Pastes `[not-now]`. */
        var nn = document.createElement('label');
        nn.className = 'kit-notnow';
        var nni = document.createElement('input');
        nni.type = first.type;
        nni.name = first.name;
        nni.setAttribute('data-label', NOT_NOW);
        var nnt = document.createElement('span');
        nnt.appendChild(document.createTextNode(L.notNow + ' '));
        var nnh = document.createElement('span');
        nnh.className = 'hint';
        nnh.textContent = L.notNowHint;
        nnt.appendChild(nnh);
        nn.appendChild(nni);
        nn.appendChild(nnt);
        g.appendChild(nn);
      });
    });
  }

  /* The ask row (BL-325 -> BL-381). "Explain this one better" began as a
   * checkbox on the item (v12), became a radio in the option group (v15, at the
   * owner's request: exclusive with answering) and split in two by kind of gap
   * (v16). Then 348 owner messages mined from every transcript showed what the
   * reader actually types when an item cannot be answered: the asks arrive
   * COMBINED ("explícamelo mejor y vuelve a darme las opciones") and ALONGSIDE
   * an answer ("Sí, pero…"), and three kinds the two markers never named. The
   * exclusivity v15 asked for is the property that failed — "en algunos casos
   * se necesitan ambas" (2026-09-09).
   *
   * So since v18 the asks are a separate SURFACE: one row on the item, after
   * its option groups, of five checkboxes with a tagged vocabulary. Ticking one
   * releases nothing. The row lives on the item rather than in a group, which
   * is also what gives it back to an item whose only surface is a value box —
   * the cost v15 stated. The general-notes item asks nothing and gets none.
   *
   * One line, not five: chips with a title each and no hint lines, because
   * the two v16 radios cost four lines per group and the whole complaint about
   * these pages is their length. Seven chips since v19; at phone width the row
   * wraps, which components.css tightens rather than hides — a disclosed chip
   * costs the one thing the mining shows the reader lacks, seeing it exists.
   *
   * Every chip is a mark with a `data-label`, so every path that handles marks
   * handles it: readItem pastes it, snapshotItem stores it, restore re-checks
   * it, clearItem clears it, copy folds it into the sent fingerprint. The term
   * box is an ordinary text input to the store (restored by order) and is kept
   * out of the free-text paste. The labels are localised; the markers are not. */
  var ASKS = [
    [EXPLAIN_STATE, 'askState', 'askStateTitle'],
    [EXPLAIN_OPTIONS, 'askOptions', 'askOptionsTitle'],
    [EXPLAIN_WHY, 'askWhy', 'askWhyTitle'],
    [EXPLAIN_SIMPLER, 'askSimpler', 'askSimplerTitle'],
    [QUESTION, 'askQuestion', 'askQuestionTitle'],
    [REFRAME, 'askReframe', 'askReframeTitle'],
    [SHOW_ME, 'askShow', 'askShowTitle']
  ];
  function addAskRows() {
    items.forEach(function (el) {
      if (isDecided(el) || el.classList.contains('consult-notes')) return;
      if (el.querySelector('.kit-ask')) return;
      var row = document.createElement('div');
      row.className = 'kit-ask';
      var lead = document.createElement('span');
      lead.className = 'kit-ask-lead';
      lead.textContent = L.askLabel;
      row.appendChild(lead);
      ASKS.forEach(function (spec) {
        var lab = document.createElement('label');
        lab.title = L[spec[2]];
        var input = document.createElement('input');
        input.type = 'checkbox';
        input.setAttribute('data-label', spec[0]);
        lab.appendChild(input);
        lab.appendChild(document.createTextNode(' ' + L[spec[1]]));
        /* `[question]` has no surface of its own: the question travels in the
         * notes, so ticking the chip puts the cursor there. The v18 chip it
         * replaces carried its own text box and was never used once in 333
         * answered items; the box the item already has is the one the reader
         * types in. */
        if (spec[0] === QUESTION) {
          input.addEventListener('change', function () {
            if (!input.checked) return;
            /* The item's own notes box first, its free-prose box second, and
             * the page's general-notes box last: an item whose only surface is
             * a value or a list has nowhere of its own to type a question, and
             * focusing nothing is how the chip would silently do nothing. */
            var box = el.querySelector('textarea') || el.querySelector('[contenteditable]')
                   || document.querySelector('.consult-notes textarea');
            if (box) box.focus();
          });
        }
        row.appendChild(lab);
      });
      /* After the LAST option group when there is one — below the answer, as
       * a second surface — else before the first field label, else at the end. */
      var groups = el.querySelectorAll('.opts');
      var anchor = groups.length ? groups[groups.length - 1] : null;
      if (anchor) anchor.parentNode.insertBefore(row, anchor.nextSibling);
      else {
        var label = el.querySelector('.fieldlabel');
        if (label) label.parentNode.insertBefore(row, label);
        else el.appendChild(row);
      }
    });
  }

  /* The provisional line, added and removed as the pair (option, ask) makes and
   * unmakes the state. Injected like every other kit affordance — a page gets
   * it by being wrapped — and stripped from the question fingerprint, or the
   * moment a reader ticked an ask beside an option the item would read as "the
   * question changed" and their stored answer would be dropped. */
  function markProvisional(el) {
    var want = isProvisional(el);
    var node = el.querySelector('.kit-provisional');
    if (want && !node) {
      node = document.createElement('p');
      node.className = 'kit-provisional';
      node.textContent = L.provisional;
      var row = el.querySelector('.kit-ask');
      if (row) row.parentNode.insertBefore(node, row.nextSibling);
      else el.appendChild(node);
    } else if (!want && node) {
      node.remove();
    }
  }

  /* A picked radio can be released by picking it again (BL-268). The browser
   * offers no way out of a radio group once one is in, and the per-item Clear
   * below also empties the notes — so a reader who changed their mind about
   * the mark alone had to retype. The state is read on mousedown, before the
   * browser flips it, and undone on the click that follows; keyboard
   * selection is untouched. */
  function releasableRadios() {
    var was = null;
    document.addEventListener('mousedown', function (ev) {
      var lab = ev.target.closest ? ev.target.closest('.consult-item label') : null;
      var r = lab ? lab.querySelector('input[type="radio"]') : null;
      if (!r && ev.target.type === 'radio') r = ev.target;
      was = (r && r.checked) ? r : null;
    });
    document.addEventListener('click', function (ev) {
      var r = ev.target;
      if (!r || r.type !== 'radio' || r !== was) return;
      was = null;
      r.checked = false;
      r.dispatchEvent(new Event('change', { bubbles: true }));
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
      if (isDecided(el)) return;
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
        /* No field label to share a row with. A plain append since v15: the
         * explain escape moved INSIDE the option group, so it is no longer a
         * child of the item and `insertBefore` against it would throw. */
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
    /* Three states, not two. A page whose every question is DECIDED leaves
     * collect() with a denominator of zero — decided items are in neither the
     * numerator nor the total — and `r.answered ? … : L.none` had exactly one
     * reachable branch there, so a reader who had just settled the last
     * question was told "nothing answered yet" over an empty question set
     * (BL-341; BL-331 had already taught the checker to accept the page).
     * Only the status changes: the general-notes box is not one of the
     * questions, so it is still fillable and the copy bar still has work. */
    if (!r.total) { say(L.allDecided); return; }
    say(r.answered
      ? L.progress(r.answered, r.total) + (r.blank.length ? L.missing(r.blank) : '')
      : L.none);
  }

  function copy() {
    var r = collect();
    /* `markdown`, not `answered`: a page whose only filled box is the general
     * notes has something to send, and `answered` deliberately no longer counts
     * that box. Refusing on the counter would make the notes unsendable. */
    if (!r.markdown) {
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

  /* The theme control (BL-327). `tokens.css` has defined the palette three
   * times since it was written — bare `:root`, the system-dark media query, and
   * `:root[data-theme="dark"|"light"]` for an explicit choice — and NOTHING has
   * ever set that attribute. Measured on a real page: `data-theme` was null and
   * `skeleton.html` never mentioned it, so a third of the palette, maintained
   * and kept in sync on every token change, had never once applied.
   *
   * The cost that makes this worth building rather than deleting the dead
   * branch: pinned to the OS setting, neither the author nor the reader ever
   * sees the other rendering, so a figure whose colours come out wrong in the
   * mode nobody looks at is invisible until someone else opens it.
   *
   * Injected here rather than written into the skeleton body, for the reason
   * every other kit affordance is: a page gets it by being wrapped.
   *
   * NO STORED CHOICE MEANS NO ATTRIBUTE. The default path is untouched — the
   * page follows `prefers-color-scheme` exactly as before, which is what the
   * `:not([data-theme="light"])` guard in the media query is written for. Only
   * a deliberate click pins it. */
  var THEME_KEY = 'aidex-kit-theme:' + location.pathname;

  function currentTheme() {
    var set = document.documentElement.getAttribute('data-theme');
    if (set) return set;
    return (window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches)
      ? 'dark' : 'light';
  }

  function themeControl() {
    var b = document.createElement('button');
    b.type = 'button';
    b.className = 'kit-theme';
    b.id = 'kit-theme';
    b.title = L.themeTitle;
    function label() {
      // Names the DESTINATION, not the state: "Verdict names the action".
      b.textContent = currentTheme() === 'dark' ? L.toLight : L.toDark;
      b.setAttribute('aria-pressed', document.documentElement.getAttribute('data-theme') ? 'true' : 'false');
    }
    b.addEventListener('click', function () {
      var next = currentTheme() === 'dark' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      try { localStorage.setItem(THEME_KEY, next); } catch (e) { /* unavailable */ }
      label();
    });
    label();
    document.body.appendChild(b);
  }

  /* ---- The gallery row: zoom, keyboard, filters (kit v20) ----------------
   *
   * A gallery row is one screen state seen in every tile of the matrix, and
   * judging it means looking at a capture at the size it was taken. Until this
   * the only way in was the image as the grid draws it — a quarter-width
   * thumbnail — or an anchor that navigated the page away and lost every
   * answer typed into it.
   *
   * So: ONE `<dialog>` per page, built here and reused by every tile. Native
   * `showModal()` rather than a hand-rolled overlay (research note, pattern 5):
   * it brings the focus trap, the backdrop and Esc for nothing, and a modal
   * without those is the accessibility defect a library would be bought for.
   *
   * The JS only ADDS attributes and listeners; it writes no markup into the
   * row. A viewer with scripts off still sees the grid and its captions, which
   * is what the static snapshot has to keep being.
   *
   * Nothing here is a reply surface. The tiles are figures, the toolbar is
   * made of `<button>`s, and the filter state lives on the BLOCK and in
   * localStorage — never in an input, or `readItem` would paste the way the
   * reader was looking at the page as if it were part of their answer. */
  var GAL_KEY = 'aidex-kit-gallery:' + location.pathname;

  /* By SHAPE, like the checker (`gallery_findings`): the rows written by hand
   * before the generator existed carry the grid and not the class, and a
   * predicate that knew only the class would go silent on exactly them. */
  function isGalleryRow(el) {
    return el.classList.contains('consult-gallery')
        || !!el.querySelector('.gal, figure[data-tile]');
  }

  /* The block's declared matrix is the keyboard order — the same list the
   * checker judges completeness against, so the arrows and the rule agree on
   * what the row's cells are. A row with no block (or a block that declares
   * nothing) falls back to the order its own figures are written in. */
  function tileOrder(row) {
    var g = row.closest('.consult-group');
    var declared = g ? (g.getAttribute('data-tiles') || '').split(/\s+/) : [];
    declared = declared.filter(Boolean);
    if (declared.length) return declared;
    return [].map.call(row.querySelectorAll('figure[data-tile]'), function (f) {
      return f.getAttribute('data-tile') || '';
    });
  }

  function tileFigure(row, name) {
    return [].filter.call(row.querySelectorAll('figure[data-tile]'), function (f) {
      return f.getAttribute('data-tile') === name;
    })[0] || null;
  }

  function gallery() {
    /* Re-queried rather than reusing `items`: decided rows have been MOVED
     * into their folds by now, and Up/Down claims DOM order. */
    var rows = [].slice.call(document.querySelectorAll('.consult-item'))
      .filter(isGalleryRow);
    var groups = [].slice.call(document.querySelectorAll('.consult-group'))
      .filter(function (g) { return (g.getAttribute('data-tiles') || '').trim(); });
    if (!rows.length && !groups.length) return;

    /* ---- the dialog ---- */
    var dlg = document.createElement('dialog');
    dlg.className = 'kit-zoom';
    var head = document.createElement('div');
    head.className = 'kit-zoom-head';
    var hRow = document.createElement('span');
    hRow.className = 'kit-zoom-row';
    var hTile = document.createElement('span');
    hTile.className = 'kit-zoom-tile';
    var hCell = document.createElement('span');
    hCell.className = 'kit-zoom-cell';
    var bSize = document.createElement('button');
    bSize.type = 'button';
    bSize.className = 'kit-zoom-size';
    bSize.title = L.zoomSizeTitle;
    var bClose = document.createElement('button');
    bClose.type = 'button';
    bClose.className = 'kit-zoom-close';
    bClose.textContent = L.zoomClose;
    bClose.title = L.zoomCloseTitle;
    head.appendChild(hRow);
    head.appendChild(hTile);
    head.appendChild(hCell);
    head.appendChild(bSize);
    head.appendChild(bClose);
    var body = document.createElement('div');
    body.className = 'kit-zoom-body';
    var img = document.createElement('img');
    body.appendChild(img);
    var keys = document.createElement('p');
    keys.className = 'kit-zoom-keys';
    keys.textContent = L.zoomKeys;
    dlg.appendChild(head);
    dlg.appendChild(body);
    dlg.appendChild(keys);
    document.body.appendChild(dlg);

    var opener = null;                /* the figure that opened it */

    function sizeLabel() {
      // Names the DESTINATION, like the theme button does.
      bSize.textContent = dlg.classList.contains('native') ? L.zoomFit : L.zoomNative;
      bSize.setAttribute('aria-pressed', dlg.classList.contains('native') ? 'true' : 'false');
    }

    function show(fig) {
      var row = fig.closest('.consult-item');
      var src = fig.querySelector('img');
      opener = fig;
      img.setAttribute('src', src ? src.getAttribute('src') : '');
      img.setAttribute('alt', src ? (src.getAttribute('alt') || '') : '');
      hRow.textContent = (row && row.dataset.title) || '';
      hTile.textContent = fig.getAttribute('data-tile') || '';
      hCell.textContent = (row && row.dataset.id) || '';
    }

    function open(fig) {
      /* Fit size on every fresh open: the reader asked to see the tile, not to
       * resume the last tile's magnification. Moving with the arrows keeps
       * whatever size is on screen — there it IS the same look, continued. */
      dlg.classList.remove('native');
      sizeLabel();
      show(fig);
      if (dlg.showModal) dlg.showModal();
      else dlg.setAttribute('open', '');   /* no modal support: still readable */
    }

    bSize.addEventListener('click', function () {
      dlg.classList.toggle('native');
      sizeLabel();
    });
    bClose.addEventListener('click', function () { dlg.close(); });
    /* Esc closes without a listener of its own; `close` fires for both paths,
     * so the focus return is written once. */
    dlg.addEventListener('close', function () {
      if (opener) opener.focus();
    });

    /* The tiles, in the order the matrix declares. A tile the row does not
     * carry is stepped OVER rather than treated as the end: a row missing a
     * cell is a defect the checker reports, and the arrows must not turn it
     * into a wall. Filters never enter here — hiding a tile is a viewing aid,
     * and a reader who navigates to a hidden cell still has to be able to
     * judge it. */
    function step(dir) {
      if (!opener) return;
      var row = opener.closest('.consult-item');
      var order = tileOrder(row);
      var i = order.indexOf(opener.getAttribute('data-tile'));
      if (i === -1) return;
      for (var j = i + dir; j >= 0 && j < order.length; j += dir) {
        var f = tileFigure(row, order[j]);
        if (f) return show(f);        /* no wrapping: the ends are the ends */
      }
    }

    /* The same tile on another row, rows in DOM order. A row that does not
     * carry this tile — the not-applicable row is the common case — is stepped
     * over for the same reason. */
    function stepRow(dir) {
      if (!opener) return;
      var row = opener.closest('.consult-item');
      var name = opener.getAttribute('data-tile');
      var i = rows.indexOf(row);
      if (i === -1) return;
      for (var j = i + dir; j >= 0 && j < rows.length; j += dir) {
        var f = tileFigure(rows[j], name);
        if (f) return show(f);
      }
    }

    dlg.addEventListener('keydown', function (ev) {
      var moves = { ArrowLeft: [step, -1], ArrowRight: [step, 1],
                    ArrowUp: [stepRow, -1], ArrowDown: [stepRow, 1] };
      var m = moves[ev.key];
      if (!m) return;
      ev.preventDefault();            /* or the dialog scrolls under the move */
      m[0](m[1]);
    });

    /* ---- every tile becomes the button ---- */
    rows.forEach(function (row) {
      row.querySelectorAll('figure[data-tile]').forEach(function (fig) {
        if (!fig.querySelector('img')) return;   /* nothing to enlarge */
        fig.setAttribute('role', 'button');
        fig.setAttribute('tabindex', '0');
        fig.setAttribute('title', L.zoomOpen);
        fig.addEventListener('click', function (ev) {
          /* The round-5 prototype wrapped each tile in an anchor that opened
           * the file in a new tab, and pages carrying that markup are still on
           * disk: the zoom must not ALSO navigate away from the answers. */
          ev.preventDefault();
          open(fig);
        });
        fig.addEventListener('keydown', function (ev) {
          if (ev.key !== 'Enter' && ev.key !== ' ' && ev.key !== 'Spacebar') return;
          ev.preventDefault();        /* Space would scroll the page */
          open(fig);
        });
      });
    });

    /* ---- the filters ---- */
    /* `data-mode` and `data-viewport`, the vocabulary the project's board
     * already speaks (`gallery_board.py`), so the page and the harness name
     * the same things. The values are set on the BLOCK and the hiding is done
     * by components.css: one attribute, no per-figure bookkeeping to drift. */
    var FILTERS = [
      { key: 'mode', label: 'galMode',
        opts: [['both', 'galBoth'], ['light', 'galLight'], ['dark', 'galDark']] },
      { key: 'viewport', label: 'galViewport',
        opts: [['both', 'galBoth'], ['desktop', 'galDesktop'], ['mobile', 'galMobile']] }
    ];

    function galState() {
      try { return JSON.parse(localStorage.getItem(GAL_KEY) || '{}') || {}; }
      catch (e) { return {}; }        /* storage refused: no filter is kept */
    }

    function galStore(id, key, value) {
      try {
        var all = galState();
        if (!all[id]) all[id] = {};
        all[id][key] = value;
        localStorage.setItem(GAL_KEY, JSON.stringify(all));
      } catch (e) { /* unavailable — the filter still applies in this tab */ }
    }

    var saved = galState();
    groups.forEach(function (g) {
      if (g.querySelector('.kit-galbar')) return;
      var gid = g.dataset.id || g.id || '';
      var bar = document.createElement('div');
      bar.className = 'kit-galbar';
      bar.title = L.galBarTitle;
      FILTERS.forEach(function (f) {
        var wrap = document.createElement('span');
        wrap.className = 'kit-galgroup';
        var lab = document.createElement('span');
        lab.className = 'kit-gallabel';
        lab.textContent = L[f.label];
        wrap.appendChild(lab);
        var btns = [];
        function apply(value, persist) {
          g.setAttribute('data-' + f.key, value);
          btns.forEach(function (b) {
            b.setAttribute('aria-pressed', b.dataset.value === value ? 'true' : 'false');
          });
          if (persist) galStore(gid, f.key, value);
        }
        f.opts.forEach(function (o) {
          var b = document.createElement('button');
          b.type = 'button';
          b.className = 'kit-galopt';
          b.dataset.value = o[0];
          b.textContent = L[o[1]];
          b.addEventListener('click', function () { apply(o[0], true); });
          btns.push(b);
          wrap.appendChild(b);
        });
        var was = saved[gid] && saved[gid][f.key];
        /* An unknown stored value would hide by a rule no button can undo. */
        var known = f.opts.some(function (o) { return o[0] === was; });
        apply(known ? was : 'both', false);
        bar.appendChild(wrap);
      });
      var afterHead = g.querySelector('.sec-head');
      if (afterHead) afterHead.parentNode.insertBefore(bar, afterHead.nextSibling);
      else g.insertBefore(bar, g.firstChild);
    });
  }

  try {
    var stored = localStorage.getItem(THEME_KEY);
    if (stored === 'dark' || stored === 'light') {
      document.documentElement.setAttribute('data-theme', stored);
    }
  } catch (e) { /* storage refused: the page still renders, on the OS setting */ }
  themeControl();
  gallery();

  fitTables();
  if (items.length) {
    addOtherChoices();
    addAskRows();
    sealDecided();
    releasableRadios();
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
