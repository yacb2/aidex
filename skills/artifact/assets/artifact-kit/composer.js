/* artifact-kit — the composer.
 *
 * Builds the rail (sections and consultation items, in body order), tracks which items
 * are answered, and composes every reply surface in an item into one markdown
 * block the reader copies in a click.
 *
 * Reply surfaces read, in this order: checked radios and checkboxes (by
 * `data-label`, falling back to `value`), selects (the selected option's text),
 * short text inputs, then textareas. An item needs at least one of them; which
 * one is the author's choice.
 *
 * Display strings are keyed off `<html lang>`, which wrap-report.sh already sets
 * from the project's `.context/profiles/artifact.md`. They are NOT hard-coded in
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
      allDecidedNothingToCopy: 'Everything is decided; write a general note if you want to send something.',
      copied: function (n) { return n + ' copied'; },
      blankList: function (ids) { return ' · ' + ids.length + ' blank: ' + ids.join(', '); },
      noneBlank: ' · none blank',
      paste: ' — paste them into the chat.',
      noClipboard: ' — clipboard unavailable, copy the selected text.',
      restored: function (n) { return n + ' answer(s) recovered from your last visit on this machine.'; },
      stale: function (n) { return ' ' + n + ' were left blank because their question changed since you answered it.'; },
      consumed: function (n) { return ' ' + n + ' were left blank because you already sent them in an earlier round.'; },
      discard: 'Discard them',
      staleTab: 'A newer version of this page is open in another tab: ',
      staleReload: 'reload this one',
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
      pageNotes: 'Notes for the whole page',
      groupNotes: 'Notes on this block',
      groupNotesPh: 'Anything about the block as a whole\u2026',
      clear: 'Clear',
      clearTitle: 'Clear this answer',
      rec: 'Recommended',
      notRec: 'Not recommended',
      recSuffix: ' (recommended)',
      notRecSuffix: ' (not recommended)',
      correct: 'Correct',
      notQuite: 'Not quite',
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
      askMore: 'more examples',
      askMoreTitle: 'I already saw examples; I want more or different ones. The ones there stay.',
      defectBtn: 'Report a page problem',
      defectLabel: 'What is wrong with the page',
      defectHead: 'Page problem',
      provisional: 'Provisional: you chose an option and asked for something as well. The next round answers the ask and keeps this question open, with that option already ticked.',
      toLight: 'Light',
      toDark: 'Dark',
      themeTitle: 'Switch this page between light and dark',
      decided: 'Decided',
      proposal: 'Decided, correct me if not',
      proposalsLeft: 'Decided points left to confirm or correct',
      proposalsNothingToCopy: 'Nothing to copy: if you agree with everything, say so in the general note',
      fixes: function (n) { return n + (n === 1 ? ' correction ready to copy' : ' corrections ready to copy'); },
      decidedCount: function (n, w) {
        var word = w === 'row' ? 'row' : w === 'item' ? 'item' : 'question';
        return n + ' ' + word + (n === 1 ? ' already settled' : 's already settled');
      },
      dropped: 'Dropped',
      droppedMark: ' (dropped)',
      droppedHint: 'These questions left the set without an answer. Open one to re-read what it asked and why it was dropped.',
      droppedCount: function (n) { return n + (n === 1 ? ' question dropped, never answered' : ' questions dropped, never answered'); },
      decidedHint: 'Collapsed so the open questions stay in view. Open one to re-read what it asked and what it chose.',
      zoomOpen: 'Open this image at full size',
      zoomLabel: 'Enlarge',
      moreOptions: 'More options',
      zoomNative: 'Native size (1:1)',
      zoomFit: 'Fit to the window',
      zoomSizeTitle: 'Switch between fitting the window and the image’s own size',
      zoomClose: 'Close',
      zoomPrev: 'Previous',
      zoomNext: 'Next',
      zoomCloseTitle: 'Close this image and go back (Esc)',
      zoomKeys: 'Left/Right: the tiles of this row · Up/Down: the same tile on the next row',
      zoomKeysShots: 'Left/Right (or swipe): the images of this question · Esc: back to it',
      zoomKeysPan: 'Left/Right: the images of this question · drag to pan the image · Esc: back to it',
      galMode: 'Mode',
      galViewport: 'Viewport',
      galBoth: 'Both',
      galLight: 'Light',
      galDark: 'Dark',
      galDesktop: 'Desktop',
      galMobile: 'Mobile',
      galBarTitle: 'Hides tiles while you read. What you copy never changes.',
      cmp: 'Compare',
      cmpOff: 'Off',
      cmp2up: '2-up',
      cmpSwipe: 'Swipe',
      cmpOnion: 'Onion skin',
      cmpTitle: 'Compare this tile with its pair: before and proposed, or the other mode of the same viewport',
      cmpNone: 'This tile has no pair in this row to compare against',
      cmpRange: 'Right: more of this tile · left: more of the other mode',
      cmpSize: function (a, b) { return 'The two captures differ in size (' + a + ' against ' + b + '): shown side by side.'; },
      markHint: 'Drag to mark a region · click a mark to edit or delete it',
      markNote: 'Note for this mark',
      markSave: 'Save',
      markDelete: 'Delete mark',
      markCancel: 'Cancel',
      markAdd: 'Mark a region',
      markAddTitle: 'Draft a region from the keyboard: arrows move it, Shift+arrows resize it, Enter adds its note, Esc drops it',
      marksTitle: 'Region notes',
      marksEmpty: 'No region notes yet: open a capture and use Mark a region to add one.',
      marksNoNote: '(no note)',
      marksOpen: 'Open this region on its capture',
      marksRemove: 'Remove',
      markKeys: 'Arrows: move the region \u00b7 Shift+arrows: resize it \u00b7 Enter: add its note \u00b7 Esc: drop it'
    },
    es: {
      none: 'Sin responder todavía.',
      allDecided: 'Todas las preguntas están decididas — no queda nada por responder.',
      progress: function (n, total) { return n + ' de ' + total + ' respondidas'; },
      missing: function (ids) {
        return ' · ' + (ids.length === 1 ? 'falta ' : 'faltan ') + ids.join(', ');
      },
      nothingToCopy: 'Todavía no has respondido nada — no hay nada que copiar.',
      allDecidedNothingToCopy: 'Todo está decidido; escribe una nota general si quieres enviar algo.',
      copied: function (n) { return n + ' copiada(s)'; },
      blankList: function (ids) { return ' · ' + ids.length + ' en blanco: ' + ids.join(', '); },
      noneBlank: ' · ninguna en blanco',
      paste: ' — pégalas en el chat.',
      noClipboard: ' — portapapeles no disponible, copia el texto seleccionado.',
      restored: function (n) { return n + ' respuesta(s) recuperada(s) de tu última visita en esta máquina.'; },
      stale: function (n) { return ' ' + n + ' se dejaron en blanco porque su pregunta cambió desde que la respondiste.'; },
      consumed: function (n) { return ' ' + n + ' se dejaron en blanco porque ya las enviaste en una ronda anterior.'; },
      discard: 'Descartarlas',
      staleTab: 'Hay una versión más nueva de esta página en otra pestaña: ',
      staleReload: 'recárgala',
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
      pageNotes: 'Notas de la p\u00e1gina',
      groupNotes: 'Notas de este bloque',
      groupNotesPh: 'Lo que afecta a todo el bloque\u2026',
      clear: 'Limpiar',
      clearTitle: 'Limpiar esta respuesta',
      rec: 'Recomendada',
      notRec: 'No recomendada',
      recSuffix: ' (recomendada)',
      notRecSuffix: ' (no recomendada)',
      correct: 'Correcto',
      notQuite: 'No exactamente',
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
      askMore: 'm\u00e1s ejemplos',
      askMoreTitle: 'Ya vi ejemplos; quiero m\u00e1s o distintos. Los que est\u00e1n se quedan.',
      defectBtn: 'Reportar un fallo de la p\u00e1gina',
      defectLabel: 'Qu\u00e9 est\u00e1 mal en la p\u00e1gina',
      defectHead: 'Fallo de la p\u00e1gina',
      provisional: 'Provisional: elegiste una opci\u00f3n y adem\u00e1s pediste algo. La pr\u00f3xima ronda responde lo que pediste y deja esta pregunta abierta, con esa opci\u00f3n ya marcada.',
      toLight: 'Claro',
      toDark: 'Oscuro',
      themeTitle: 'Cambia esta p\u00e1gina entre claro y oscuro',
      decided: 'Decidido',
      proposal: 'Decidido, corr\u00edgeme si no',
      proposalsLeft: 'Quedan puntos decididos por confirmar o corregir',
      proposalsNothingToCopy: 'Nada que copiar: si est\u00e1s de acuerdo con todo, escr\u00edbelo en la nota general',
      fixes: function (n) { return n + (n === 1 ? ' correcci\u00f3n lista para copiar' : ' correcciones listas para copiar'); },
      decidedCount: function (n, w) {
        var word = w === 'row' ? 'fila' : w === 'item' ? 'elemento' : 'pregunta';
        var done = w === 'item' ? 'resuelto' : 'resuelta';
        return n + ' ' + word + (n === 1 ? ' ya ' + done : 's ya ' + done + 's');
      },
      dropped: 'Descartadas',
      droppedMark: ' (descartada)',
      droppedHint: 'Estas preguntas salieron del conjunto sin respuesta. Abre una para releer qu\u00e9 preguntaba y por qu\u00e9 se descart\u00f3.',
      droppedCount: function (n) { return n + (n === 1 ? ' pregunta descartada, sin responder' : ' preguntas descartadas, sin responder'); },
      decidedHint: 'Plegadas para que las preguntas abiertas queden a la vista. Abre una para releer qu\u00e9 preguntaba y qu\u00e9 se eligi\u00f3.',
      zoomOpen: 'Abre esta imagen a tama\u00f1o completo',
      zoomLabel: 'Ampliar',
      moreOptions: 'M\u00e1s opciones',
      zoomNative: 'Tama\u00f1o original (1:1)',
      zoomFit: 'Ajustar a la ventana',
      zoomSizeTitle: 'Alterna entre ajustar a la ventana y el tama\u00f1o propio de la imagen',
      zoomClose: 'Cerrar',
      zoomPrev: 'Anterior',
      zoomNext: 'Siguiente',
      zoomCloseTitle: 'Cierra esta imagen y vuelve (Esc)',
      zoomKeys: 'Izquierda/Derecha: las capturas de esta fila \u00b7 Arriba/Abajo: la misma captura en la fila siguiente',
      zoomKeysShots: 'Izquierda/Derecha (o desliza): las im\u00e1genes de esta pregunta \u00b7 Esc: volver a ella',
      zoomKeysPan: 'Izquierda/Derecha: las im\u00e1genes de esta pregunta \u00b7 arrastra para mover la imagen \u00b7 Esc: volver a ella',
      galMode: 'Modo',
      galViewport: 'Pantalla',
      galBoth: 'Ambos',
      galLight: 'Claro',
      galDark: 'Oscuro',
      galDesktop: 'Escritorio',
      galMobile: 'M\u00f3vil',
      galBarTitle: 'Oculta capturas mientras lees. Lo que copias no cambia.',
      cmp: 'Comparar',
      cmpOff: 'No',
      cmp2up: 'Lado a lado',
      cmpSwipe: 'Deslizar',
      cmpOnion: 'Superponer',
      cmpTitle: 'Compara esta captura con su par: antes y propuesto, o el otro modo de la misma pantalla',
      cmpNone: 'Esta captura no tiene par en esta fila con el que compararse',
      cmpRange: 'Derecha: m\u00e1s de esta captura \u00b7 izquierda: m\u00e1s del otro modo',
      cmpSize: function (a, b) { return 'Las dos capturas tienen tama\u00f1os distintos (' + a + ' frente a ' + b + '): se muestran lado a lado.'; },
      markHint: 'Arrastra para marcar una zona \u00b7 haz clic en una marca para editarla o borrarla',
      markNote: 'Nota para esta marca',
      markSave: 'Guardar',
      markDelete: 'Borrar marca',
      markCancel: 'Cancelar',
      markAdd: 'Marcar zona',
      markAddTitle: 'Dibuja una zona con el teclado: las flechas la mueven, May\u00fas+flechas cambian su tama\u00f1o, Intro a\u00f1ade su nota, Esc la descarta',
      marksTitle: 'Notas de zona',
      marksEmpty: 'A\u00fan no hay notas de zona: abre una captura y usa Marcar zona para a\u00f1adir una.',
      marksNoNote: '(sin nota)',
      marksOpen: 'Abrir esta zona en su captura',
      marksRemove: 'Quitar',
      markKeys: 'Flechas: mover la zona \u00b7 May\u00fas+flechas: cambiar su tama\u00f1o \u00b7 Intro: a\u00f1adir su nota \u00b7 Esc: descartarla'
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
   * examples explicitly instead.
   *
   * Two more (BL-505): `[more-examples]` is NOT the `[show-examples]` proposal
   * above widened back in — `[show-me]` answers "I have no example yet", this
   * answers "I have one and want more or different ones, the ones given stay",
   * and its rewrite duty and its gate (the example count must grow) differ from
   * show-me's, so widening would have lost that gate. `[page-defect]` names a
   * defect IN THE PAGE ITSELF (broken text, something that fails to render) —
   * no other chip says that, `[reframe]` says the QUESTION is wrong, which is a
   * different claim and pulled in the wrong rewrite (a different question,
   * rather than the same page fixed in place). */
  var EXPLAIN_WHY = '[explain-why]';
  var EXPLAIN_SIMPLER = '[explain-simpler]';
  var QUESTION = '[question]';
  var REFRAME = '[reframe]';
  var SHOW_ME = '[show-me]';
  var MORE_EXAMPLES = '[more-examples]';
  var NOT_NOW = '[not-now]';
  /* Not a chip and never ticked: a qualifier the composer appends to a chosen
   * option when an ask sits beside it. See isProvisional. */
  var PROVISIONAL = '[provisional]';
  /* A short-value box: any text-like <input>, not only a literal type="text".
   * check_artifact accepts an <input> with no type as a reply surface, and an
   * attribute selector never matches an attribute that is not written, so a
   * typeless or number box was neither counted, pasted nor stored (C-c08).
   * Enumerated rather than "not radio/checkbox": the kit's own range slider is
   * an <input> too and is not an answer. */
  var SHORT_VALUE = 'input:not([type]), input[type="text"], input[type="number"], ' +
    'input[type="date"], input[type="email"], input[type="url"]';

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
    ['.fieldlabel', 'text', 'pageNotes'],
    ['.fieldlabel', 'text', 'groupNotes'],
    ['textarea', 'placeholder', 'notesPh'],
    ['textarea', 'placeholder', 'listPh'],
    ['textarea', 'placeholder', 'valuePh'],
    ['textarea', 'placeholder', 'generalPh'],
    ['textarea', 'placeholder', 'groupNotesPh']
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
   * else to say so. Bare `data-decided` keeps the derived line. The fold is
   * text, so a verdict written `**x**` shows plain, the same [`*] strip as the
   * builder's PLAIN (md_body.py) (BL-545). */
  function decidedSummary(el) {
    var v = (el.getAttribute('data-decided') || '').replace(/[`*]/g, '').trim();
    return v || decidedLine(el);
  }

  /* BL-629: the reply to the owner's note on a decided row (data-answer) rides in
   * the fold's summary, so it is read without opening the fold. */
  function answerOf(el) { return (el.getAttribute('data-answer') || '').trim(); }

  var decidedSection = null, droppedSection = null;
  /* A dropped item (data-dropped, BL-516.4) left the question set unanswered:
   * it is folded like a decided one, but it is not a decision, so it is counted
   * and headed apart from them (BL-532). */
  function isDropped(el) { return el.hasAttribute('data-dropped'); }
  function collapseDecided() {
    var decided = items.filter(isSettled);
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
        var all = [].slice.call(g.querySelectorAll('.consult-item')).every(isSettled);
        if (all) {
          if (seen.indexOf(g) === -1) { seen.push(g); units.push({ node: g, group: true }); }
          return;
        }
        inPlace.push(el);             /* block still open — fold the item where it is */
        return;
      }
      units.push({ node: el, group: false });
    });
    units.forEach(function (u) {
      u.dropped = u.group
        ? [].slice.call(u.node.querySelectorAll('.consult-item')).every(isDropped)
        : isDropped(u.node);
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
        /* Each row: its title, then the verdict as written on it (BL-608), dropped
         * rows included (their data-decided reads "Descartada: reason"). The id and
         * the generic droppedMark are fallbacks, never the first choice. */
        v.textContent = (u.node.dataset.title || '') + ' \u2014 ' +
          inner.map(function (el) {
            var verdict = decidedSummary(el) || (isDropped(el) ? L.droppedMark.trim() : '');
            var ans = answerOf(el);
            return (el.dataset.heading || el.dataset.title || el.dataset.id) + (verdict ? ': ' + verdict : '') + (ans ? ' \u2014 ' + ans : '');
          }).join('\n');
        v.className += ' decided-lines';
      } else {
        /* A row with a heading is labelled by it (BL-577); the slug stays on data-id. */
        k.textContent = u.node.dataset.heading ? '' : (u.node.dataset.id || '');
        var line = decidedSummary(u.node);
        v.textContent = (u.node.dataset.heading || u.node.dataset.title || '') + (line ? ' \u2014 ' + line : '');
      }
      if (k.textContent) sum.appendChild(k);
      sum.appendChild(v);
      if (!u.group && answerOf(u.node)) {
        var a = document.createElement('span');
        a.className = 'decided-verdict decided-answer';
        a.textContent = '\u2014 ' + answerOf(u.node);
        sum.appendChild(a);
      }
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

    function section(id, cls, eyebrowText, headText, hintText, list) {
      var sec = document.createElement('section');
      claimId(sec, id);
      sec.className = cls;
      var head = document.createElement('div');
      head.className = 'sec-head';
      var eyebrow = document.createElement('p');
      eyebrow.className = 'eyebrow';
      eyebrow.textContent = eyebrowText;
      var h2 = document.createElement('h2');
      h2.textContent = headText;
      head.appendChild(eyebrow);
      head.appendChild(h2);
      sec.appendChild(head);
      var hint = document.createElement('p');
      hint.className = 'decided-hint';
      hint.textContent = hintText;
      sec.appendChild(hint);
      list.forEach(function (u) {
        var d = fold(u);
        d.appendChild(u.node);          /* MOVED, not copied and not deleted */
        sec.appendChild(d);
      });
      return sec;
    }

    /* After the ledger when there is one, else after the header: the reader
     * meets what is settled before what is still being asked, and the open
     * blocks keep the run of the page to themselves. */
    var after = document.getElementById('sec-ledger') ||
                document.querySelector('.main > header');
    function place(sec) {
      if (after && after.parentNode) after.parentNode.insertBefore(sec, after.nextSibling);
      else (document.querySelector('.main') || document.body).appendChild(sec);
      after = sec;
    }
    var settled = units.filter(function (u) { return !u.dropped; });
    var gone = units.filter(function (u) { return u.dropped; });
    /* Counts are what each section HOLDS: a dropped item inside a block that is
     * otherwise decided stays in that block's unit, marked with its written
     * verdict in the summary, and is neither a decision nor counted as a dropped
     * section item. A row to redo is a verdict, not a drop: decided="Se rehace…". */
    function held(list) {
      return list.reduce(function (n, u) {
        return n + (u.group ? u.node.querySelectorAll('.consult-item').length : 1);
      }, 0);
    }
    /* Gallery rows are rows, not questions: say so when every counted entry is
     * one, and use the neutral word when the two are mixed. */
    var shown = [];
    settled.forEach(function (u) {
      if (u.group) shown = shown.concat([].slice.call(u.node.querySelectorAll('.consult-item')).filter(function (el) { return !isDropped(el); }));
      else shown.push(u.node);
    });
    var mixedDropped = settled.reduce(function (n, u) {
      return n + (u.group ? [].slice.call(u.node.querySelectorAll('.consult-item')).filter(isDropped).length : 0);
    }, 0);
    var galleryRows = shown.filter(function (el) { return el.classList.contains('consult-gallery'); }).length;
    var countWord = !galleryRows ? 'question' : galleryRows === shown.length ? 'row' : 'item';
    if (settled.length) {
      place(decidedSection = section('sec-decided', 'decided',
        L.decidedCount(held(settled) - mixedDropped, countWord),
        L.decided, L.decidedHint, settled));
    }
    if (gone.length) {
      place(droppedSection = section('sec-dropped', 'decided dropped',
        L.droppedCount(held(gone)),
        L.dropped, L.droppedHint, gone));
    }
  }
  collapseDecided();

  // The rail carries the sections as well as the questions: on a read with no
  // questions it is still the index, which is why it stays on every page.
  // A BLOCK (`section.consult-group`, BL-247) is a section whose decisions are
  // listed right under it, indented — one entry for the context, its items
  // below, never a second entry for the same context elsewhere. Items outside
  // any block (the general notes) are listed where the body has them, after a
  // separator.
  var links = new Array(items.length);
  /* Every id the composer assigns goes through here. An item's anchor is its
   * dataset.id, unless another element already holds that id (the block's own id,
   * an authored anchor, a nested block given its dataset.id below, a second item
   * with the same dataset.id): then the first free `<id>-<n>`. The kit's own
   * chrome (sec-decided, consult-restored, kit-theme) yields the same way to an
   * author who used the name first. A page never carries one id twice, and the
   * rail links to the id the element really got, so the link still lands on
   * it. A declaration, so the chrome built above this line can call it. */
  function claimId(el, want) {
    var id = want, n = 2, held;
    while ((held = document.getElementById(id)) && held !== el) id = want + '-' + n++;
    el.id = id;
  }
  function itemLink(el) {
    claimId(el, el.dataset.id);
    var i = items.indexOf(el);
    if (!list) return;
    /* A decided item folded in place gets no entry (BL-380): its block is the
     * way in, and listing it would put the answered question back in the
     * index the reader asked to stop navigating. links[i] stays undefined,
     * which collect() already tolerates. */
    if (isDecided(el) && el.closest('.consult-group')) return;
    /* Nor does anything under [hidden]: drawn as nothing, its rect top is 0 and
     * the scroll spy would mark it current ahead of the section the reader is in. */
    if (el.closest('[hidden]')) return;
    var cls = el.closest('.consult-group') ? 'railitem sub' : 'railitem';
    /* A row with a human heading (data-heading, a gallery row) lists by it and
     * without its slug id: the id stays the anchor and what a reply names. */
    var badge = el.querySelector('.consult-id');
    var a = railLink(cls, '#' + el.id, el.dataset.heading ? '' : ((badge && badge.textContent.trim()) || el.dataset.id),
                     el.dataset.heading || el.dataset.title || '');
    list.appendChild(a);
    links[i] = a;
  }
  if (list) {
    function groupEntry(sec) {
      var h = sec.querySelector('h2, h3');
      if (!sec.id && sec.dataset.id) claimId(sec, sec.dataset.id);
      if (!sec.closest('[hidden]')) list.appendChild(railLink('railitem sec grp', '#' + sec.id, '', h ? h.textContent : (sec.dataset.title || '')));
      sec.querySelectorAll('.consult-item').forEach(itemLink);
    }
    function isLoose(el) {
      return !el.closest('.consult-group') && !(decidedSection && decidedSection.contains(el)) &&
             !(droppedSection && droppedSection.contains(el));
    }
    /* A loose item is listed where the body has it; the separator marks the
     * boundary between a section or block entry and a run of loose items. */
    function looseLink(el) {
      var last = list.lastElementChild;
      if (!el.closest('[hidden]') && last && (last.classList.contains('sec') || last.classList.contains('sub'))) {
        var sep = document.createElement('div');
        sep.className = 'railsep';
        list.appendChild(sep);
      }
      itemLink(el);
    }
    /* ONE walk in document order, so the rail never disagrees with the body
     * about what comes first (a loose item has no id until itemLink claims it,
     * which is why the walk is not limited to `section[id]`). */
    document.querySelectorAll('.main > section').forEach(function (sec) {
      if (sec.id && sec.classList.contains('consult-group')) return groupEntry(sec);
      if (sec.classList.contains('consult-item')) {
        if (isLoose(sec)) looseLink(sec);
        return;
      }
      var h = sec.querySelector('h2');
      if (!h || !sec.id) return;
      /* A hidden section gets no entry; its items still claim their ids below. */
      if (!sec.hidden) list.appendChild(railLink('railitem sec', '#' + sec.id, '', h.textContent));
      /* The collapsed section gets ONE entry and stops there. Listing what it
       * holds would put every answered question back in the index the reader
       * asked to stop navigating (BL-373); the section itself is the way in. */
      if (sec === decidedSection || sec === droppedSection) return;
      // Blocks and loose items wrapped in a container section still list under it.
      sec.querySelectorAll('.consult-group, .consult-item').forEach(function (el) {
        if (el.classList.contains('consult-group')) groupEntry(el);
        else if (isLoose(el)) looseLink(el);
      });
    });
    /* A loose item outside every listed section still gets its entry, last. */
    items.forEach(function (el, i) { if (!links[i] && isLoose(el)) looseLink(el); });
  } else {
    items.forEach(function (el) { claimId(el, el.dataset.id); });
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
      /* At the very bottom the last entry is current: a short last section
       * never reaches the reading line, however far the reader scrolls. A page
       * that does not scroll at all keeps the line rule (BL-488). */
      var de = document.documentElement;
      if (window.scrollY > 0 && window.scrollY + de.clientHeight >= de.scrollHeight - 2) {
        /* The last section in the PAGE, which is not always the last rail
         * entry: a loose item outside every section is still listed last. */
        found = spy.reduce(function (best, p) {
          return p.target.getBoundingClientRect().top > best.target.getBoundingClientRect().top ? p : best;
        });
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
      /* The entry AFTER the current one is kept in view too (BL-599): with
       * only the current entry shown, the general notes listed last stayed
       * below the list's edge until the page bottom. Capped so keeping the
       * next entry never pushes the current one's top out; the separator is skipped. */
      var next = current.nextElementSibling;
      while (next && !next.classList.contains('railitem')) next = next.nextElementSibling;
      var bottom = top + cr.height;
      if (next) bottom = Math.min(next.getBoundingClientRect().bottom - lr.top + list.scrollTop, top + list.clientHeight);
      if (top < list.scrollTop) list.scrollTop = top;
      else if (bottom > list.scrollTop + list.clientHeight) {
        list.scrollTop = bottom - list.clientHeight;
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

  /* A PROPOSAL (data-proposal, BL-692) is a decided item the reader has not
   * answered: the main session's "decidido, corrígeme si no". It is decided for
   * the counts (no question, no blank), but it stays drawn in place with a label,
   * its options LIVE with the proposed one pre-selected (BL-700: sealed radios
   * read as broken), and its notes box live: a typed note, or a selection
   * changed away from the proposed one, is the correction and the only thing it
   * adds to the reply (see collect() and replyBody()). */
  function isProposal(el) { return isDecided(el) && el.hasAttribute('data-proposal'); }
  /* The proposed selection as the page shipped it, captured before restore()
   * touches anything, read from the `checked` ATTRIBUTE (defaultChecked): a
   * same-tab reload makes the browser restore the reader's option into the live
   * `:checked` state before this script runs (BL-700); the reader's selection is a correction only when it
   * differs from this (BL-700). */
  var propBase = {};
  function selSig(el, byDefault) {
    return [].filter.call(el.querySelectorAll('input[type="radio"], input[type="checkbox"]'),
      function (i) { return byDefault ? i.defaultChecked : i.checked; })
      .map(function (i) { return i.dataset.label || i.value || ''; }).sort().join('\u0001');
  }
  function selChanged(el) { return isProposal(el) && selSig(el) !== propBase[el.dataset.id]; }
  /* What an item adds to the reply. A proposal with its proposed option still
   * selected adds only its typed note; once the selection differs it adds what
   * an answered item does (the option plus the note). */
  function replyBody(el) {
    if (!isProposal(el)) return withDefect(el, readItem(el));
    if (selChanged(el)) return readItem(el);
    return [].map.call(el.querySelectorAll('textarea'), function (t) { return t.value.trim(); }).filter(Boolean).join('\n\n');
  }
  /* Settled by an earlier round's answer: what collapseDecided folds away. */
  function isSettled(el) { return isDecided(el) && !isProposal(el); }

  function sealDecided() {
    document.querySelectorAll('.consult-group').forEach(function (g) {
      var t = groupNoteBox(g);
      if (t && groupSettled(g)) t.disabled = true;
    });
    items.forEach(function (el) {
      if (!isDecided(el)) return;
      el.querySelectorAll('input, select, textarea').forEach(function (i) {
        i.disabled = !isProposal(el);
      });
      if (isProposal(el)) propBase[el.dataset.id] = selSig(el, true);
      if (isProposal(el) && !el.querySelector('.consult-proposal')) {
        var tag = document.createElement('p');
        tag.className = 'consult-proposal';
        tag.textContent = L.proposal;
        var h3 = el.querySelector('h3');
        if (h3) h3.parentNode.insertBefore(tag, h3.nextSibling);
        else el.insertBefore(tag, el.firstChild);
      }
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
   * typed beside prose leaves the item plainly open — nothing to qualify.
   *
   * The page-defect report (BL-505, now its own box) is no ask chip at all: it
   * reports a defect IN THE PAGE, not a gap in the question, so it never puts a
   * chosen answer in question — the answer stands, only the rendering needs fixing. */
  function answerMarks(el) {
    return [].slice.call(el.querySelectorAll(
      '.opts input[type="radio"]:checked, .opts input[type="checkbox"]:checked'
    )).filter(function (i) { return (i.dataset.label || i.value || '') !== NOT_NOW; });
  }

  function answerValues(el) {
    return [].slice.call(el.querySelectorAll('select, ' + SHORT_VALUE))
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
    el.querySelectorAll(SHORT_VALUE).forEach(function (i) {
      if (i.value.trim()) parts.push(i.value.trim() + (prov ? ' ' + PROVISIONAL : ''));
    });
    el.querySelectorAll('[contenteditable]').forEach(function (c) {
      if (c.textContent.trim()) parts.push(c.textContent.trim());
    });
    el.querySelectorAll('textarea:not(.kit-defect-text)').forEach(function (t) {
      if (t.value.trim()) parts.push(t.value.trim());
    });
    return parts.join('\n\n');
  }

  /* The page-defect report (LOOP-008 Q10) is not part of the answer: it has its
   * own box (`.kit-defect-text`), readItem never reads it, so it does not make
   * the item answered or provisional. It travels as a labelled sub-block at the
   * END of the item's `### ` block, text verbatim. */
  function defectText(el) {
    var t = el.querySelector('textarea.kit-defect-text');
    return t ? t.value.trim() : '';
  }
  function withDefect(el, body) {
    var d = defectText(el);
    return d ? (body ? body + '\n\n' : '') + '#### ' + L.defectHead + '\n\n' + d : body;
  }

  /* `n` counts ITEMS. The markdown array also carries one `## G1 · title` line
   * per block, and reporting ITS length said "12 de 9" on a nine-item page —
   * every block touched was counted as an answer (BL-268). */
  /* A block's own free text (BL-701): the `.group-notes` box that closes each
   * `.consult-group`. It is not an item (no id, no rail link, never counted as
   * a question), so every place that walks `items` has to be told about it
   * here instead. Its text travels in the paste right under the block's `## `
   * heading, before the `### ` item blocks: a `### ` heading would read as an
   * item answer, and text after the last item's block would be read as that
   * item's own notes. An empty box adds nothing, not even the heading. */
  function groupNoteBox(g) { return g.querySelector('.group-notes textarea'); }
  function groupNoteText(g) { var t = groupNoteBox(g); return t ? t.value.trim() : ''; }
  function groupHead(g) {
    var head = '## ' + (g.dataset.id || g.id || '') + ' · ' + (g.dataset.title || ''), note = groupNoteText(g);
    return note ? head + '\n\n' + note : head;
  }
  /* A block whose items are ALL settled folds into the decided section: nothing is asked of it
   * any more, so its note is neither stored, restored, nor pasted, like a settled item's. */
  function groupSettled(g) {
    var its = [].slice.call(g.querySelectorAll('.consult-item'));
    return its.length > 0 && its.every(isSettled);
  }
  function noteGroups() {
    return [].slice.call(document.querySelectorAll('.consult-group'))
      .filter(function (g) { return groupNoteBox(g) && !groupSettled(g); });
  }

  function collect() {
    var answered = [], blank = [], lastGroup = null, n = 0, total = 0, proposals = 0, fixed = 0;
    /* `nodes` runs beside `answered`: the page node each chunk came from, so a
     * block whose only filled box is its own notes can be slotted in at the
     * block's place in the page rather than at the end. */
    var nodes = [], headed = [];
    function put(node, text) { answered.push(text); nodes.push(node); }
    function putHead(g) { put(g, groupHead(g)); headed.push(g); lastGroup = g; }
    items.forEach(function (el, i) {
      /* The general-notes item is NOT one of the questions, and counting it as
       * one made the page ask for something it never asked for: a reader who
       * answered every question still read "3 de 4 · en blanco: notes", and the
       * box that exists for what does not fit anywhere was reported as an
       * omission. It leaves the numerator, the denominator and the blank list;
       * its text still travels in the paste when it is filled. */
      if (isDecided(el)) {
        /* Shown as settled in the rail, counted nowhere, pasted never. A
         * proposal pastes only what the reader typed to correct it, and is
         * still counted nowhere (BL-692). */
        /* A proposal with no correction typed is pending the reader's
         * confirmation: it is not marked answered until something is typed
         * (BL-692). A proposal inside a group has no rail link, so only the
         * item's has-answer class moves; the rail has no "pending" state. */
        var fix = isProposal(el) ? replyBody(el) : '';
        if (isProposal(el)) { proposals++; if (fix) fixed++; }
        var shown = isProposal(el) ? !!fix : true;
        el.classList.toggle('has-answer', shown);
        if (links[i]) links[i].classList.toggle('done', shown);
        if (fix) {
          var pg = el.closest('.consult-group');
          if (pg && pg !== lastGroup) putHead(pg);
          put(el, '### ' + el.dataset.id + ' \u00b7 ' + (el.dataset.title || '') + '\n\n' + fix);
        }
        return;
      }
      /* A gallery SAMPLE (a row with no verdict group, by design — BL-466)
       * asks nothing either: counting it reported "1 de 2 · falta <sample>"
       * on a page whose one question was answered. It leaves the counts the
       * same way the general notes do; its notes still travel in the paste. */
      var notes = el.classList.contains('consult-notes')
        || (isGalleryRow(el) && !el.querySelector('.opts'));
      markProvisional(el);
      var body = readItem(el);
      el.classList.toggle('has-answer', !!body);
      /* A report alone is no answer, but Clear must reach it (components.css). */
      el.classList.toggle('has-defect', !!defectText(el));
      if (links[i]) links[i].classList.toggle('done', !!body);
      if (!notes) total++;
      if (body) {
        if (!notes) n++;
        /* The pasted reply keeps the block: `## G1 · title` before the first
         * answered item of each block, so the session that reads it sees the
         * grouping the reader answered under, not a flat list of ids. */
        var g = el.closest('.consult-group');
        if (g && g !== lastGroup) putHead(g);
        put(el, '### ' + el.dataset.id + ' · ' + (el.dataset.title || '') + '\n\n' + withDefect(el, body));
      }
      else {
        if (!notes) blank.push(el.dataset.id);
        /* A defect alone still travels: the item is unanswered, the report is not. */
        if (defectText(el)) {
          var dg = el.closest('.consult-group');
          if (dg && dg !== lastGroup) putHead(dg);
          put(el, '### ' + el.dataset.id + ' · ' + (el.dataset.title || '') + '\n\n' + withDefect(el, ''));
        }
      }
    });
    /* A block with a note and no answered item still owes its heading + note. */
    noteGroups().forEach(function (g) {
      if (headed.indexOf(g) !== -1 || !groupNoteText(g)) return;
      var at = nodes.findIndex(function (x) { return g.compareDocumentPosition(x) & 4; });
      if (at === -1) at = nodes.length;
      answered.splice(at, 0, groupHead(g));
      nodes.splice(at, 0, g);
    });
    return { markdown: answered.join('\n\n'), answered: n, blank: blank,
             total: total, proposals: proposals, fixed: fixed };
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
    { k: 't', q: SHORT_VALUE },
    { k: 'c', q: '[contenteditable]' },
    { k: 'a', q: 'textarea:not(.kit-defect-text)' },
    { k: 'd', q: 'textarea.kit-defect-text' }
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

  function questionHash(el, legacyLabel) {
    var clone = el.cloneNode(true);
    clone.querySelectorAll('[contenteditable]').forEach(function (c) { c.textContent = ''; });
    /* Chrome this file injects — the recommendation badges and the per-item
     * clear button — is removed before hashing. Not cosmetic: it is text inside
     * the item, so leaving it in would change every fingerprint the moment the
     * kit gained these controls, and every answer stored by a reader mid-thread
     * would read as "the question changed" and be dropped on the upgrade. */
    clone.querySelectorAll('.kit-tag, .consult-proposal, .consult-clear, .kit-other, .kit-notnow, .kit-ask, .kit-defect, .kit-feedback, .kit-more, .kit-provisional, .kit-marks-tile, .kit-marks-list, .consult-kicker').forEach(function (c) { c.remove(); });
    /* The generator's own <details> keeps its radios in the question (a row
     * built before it existed hashed them flat), but its summary word is chrome:
     * left in, every stored gallery answer would read as a changed question. */
    clone.querySelectorAll('details.opts-more > summary').forEach(function (c) { c.remove(); });
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
    if (legacyLabel !== undefined) {
      clone.querySelectorAll('.fieldlabel').forEach(function (c) { c.textContent = legacyLabel; });
    }
    /* The id badge prints the item's id, so it IS the id, not question text: a
     * kit that relabels the default notes badge (notes -> notas on an es page)
     * must not make every stored note read as "the question changed". Every
     * badge before that equalled data-id, so older hashes stay byte-identical. */
    clone.querySelectorAll('.consult-id').forEach(function (c) { c.textContent = el.dataset.id || ''; });
    var text = (clone.textContent || '').replace(/\s+/g, ' ').trim();
    /* A gallery row's question is also WHAT IT SHOWS: a round that re-captures
     * a tile under the same text is a new question, so the marks drawn on the
     * old capture never come back onto a different screenshot. Only a row with
     * tiles gains the suffix, so every other item hashes as it always did. */
    var srcs = [].map.call(el.querySelectorAll('figure[data-tile] img'), function (i) {
      return i.getAttribute('src') || '';
    });
    if (srcs.length) text += ' ' + srcs.join(' ');
    return fnv(text);
  }

  /* BL-701 reworded the page-level notes label. A general note stored under the
   * old wording is the same question, so the stored fingerprint is also tried with
   * each wording a page could have carried: the kit's English default (a hand-written
   * page, or an English spec build) and spec_build's old Spanish one. A notes item
   * that had no label at all cannot be matched this way: adding the label moves it. */
  var LEGACY_PAGE_LABELS = ['Anything that does not fit above', 'Lo que no encaja arriba'];
  function legacyNotesMatch(el, h) {
    return el.classList.contains('consult-notes') && LEGACY_PAGE_LABELS.some(function (l) {
      return h === questionHash(el, l);
    });
  }

  function snapshotItem(el) {
    var s = { m: [] }, any = false;
    if (isDecided(el) && !isProposal(el)) return null;
    /* A proposal keeps only what the reader did: its pre-selected option is the
     * writer's and must not make the item look answered, so the selection is
     * stored only once it differs from the proposed one (BL-692, BL-700). */
    el.querySelectorAll(isProposal(el) && !selChanged(el) ? 'x-none' : 'input[type="radio"]:checked, input[type="checkbox"]:checked')
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
      if (copied[el.dataset.id] === fnv(replyBody(el))) s.x = 1;
    }
    return any ? s : null;
  }

  /* A block's note is stored beside the items under `group:<id>` (BL-701), with
   * the same round / sent / fingerprint fields: the fingerprint is the block's
   * title, so a renamed block does not get a note typed under the old name. The
   * sent flag compares the copied text with the box's CURRENT text, as for items. */
  function groupKey(g) { return 'group:' + (g.dataset.id || g.id || ''); }
  function groupTitleHash(g) { return fnv(g.dataset.title || ''); }

  function save() {
    try {
      var data = {};
      items.forEach(function (el) {
        var s = snapshotItem(el);
        if (s) data[el.dataset.id] = s;
      });
      noteGroups().forEach(function (g) {
        var note = groupNoteText(g);
        if (!note) return;
        var s = { a: [groupNoteBox(g).value], h: groupTitleHash(g) };
        if (ROUND) s.r = ROUND;
        if (copied[groupKey(g)] === fnv(note)) s.x = 1;
        data[groupKey(g)] = s;
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
        /* A decided row is not a question: its round-1 answer is settled, and its
         * text changed by design (BL-629), so it is neither restored nor "stale". */
        if (isDecided(el) && !isProposal(el)) return;
        /* A proposal restores only a correction typed in THIS round: an earlier
         * round's note was about the open question, not about the writer's
         * proposal; a stored selection is restored (it is only ever saved when
         * it differs from the proposed one), the pre-selected one never is
         * the reader's answer (BL-692, BL-700). */
        if (isProposal(el) && s.r && ROUND && s.r !== ROUND) return;
        /* No `h` means an answer set saved before this existed. It is restored,
         * not discarded: upgrading the kit must not blank answers a reader
         * already typed, and the first input event re-saves the entry with a
         * fingerprint. */
        if (s.h && s.h !== questionHash(el) && !legacyNotesMatch(el, s.h)) { stale++; return; }
        /* Both rounds must be known before this can drop anything: an entry
         * saved before rounds existed has no `r`, and a page that predates the
         * marker has no ROUND. Either way the answer comes back, because
         * upgrading the kit must never blank what a reader already typed. */
        if (s.x && s.r && ROUND && s.r !== ROUND) { spent++; return; }
        var hit = false;
        /* A stored proposal selection REPLACES the proposed one (a checkbox
         * group would otherwise keep the proposed boxes ticked beside it). */
        if (isProposal(el) && [].some.call(el.querySelectorAll('input[type="radio"], input[type="checkbox"]'),
              function (i) { return (s.m || []).indexOf(i.dataset.label || i.value || '') !== -1; })) {
          el.querySelectorAll('input[type="radio"], input[type="checkbox"]').forEach(function (i) { i.checked = false; });
        }
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
          if (s.x) copied[el.dataset.id] = fnv(replyBody(el));
        }
      });
      noteGroups().forEach(function (g) {
        var s = data[groupKey(g)];
        if (!s || !s.a || !s.a[0] || !s.a[0].trim()) return;
        if (s.h && s.h !== groupTitleHash(g)) { stale++; return; }
        if (s.x && s.r && ROUND && s.r !== ROUND) { spent++; return; }
        groupNoteBox(g).value = s.a[0];
        n++;
        if (s.x) copied[groupKey(g)] = fnv(s.a[0].trim());
      });
    } catch (e) { return { n: 0, stale: 0, spent: 0 }; }
    return { n: n, stale: stale, spent: spent };
  }

  /* BL-635. Each round re-opens the same file in a new tab, and the older tabs
   * never said they were old. On load the page records its build stamp under
   * its own path; a `storage` event from another tab carrying a LATER stamp for
   * the same path marks this tab stale. The stamp is wrap_report.py's
   * "YYYY-MM-DD HH:MM" (fixed width, so a string comparison orders it), with
   * round and file mtime as tie-breaks (see newer()); an equal or older one
   * shows nothing, and a tab never reacts to its own write
   * (the event does not fire in the writing tab). No stamp meta, or storage
   * that throws, means no watch. */
  function watchStaleTab() {
    var bm = document.querySelector('meta[name="artifact-built"]');
    var built = bm ? (bm.getAttribute('content') || '') : '';
    if (!built) return;
    var key = 'aidex-kit-built:' + location.pathname;
    function num(v) { var n = parseInt(v, 10); return isNaN(n) ? 0 : n; }
    function parse(raw) {
      var o = {};
      try { o = JSON.parse(raw) || {}; } catch (e) {}
      return { b: o.b || '', r: num(o.r), m: num(o.m) };
    }
    /* The stamp has minute resolution, so a re-wrap inside the same minute ties
     * on it: then the round decides (a number), then the file's own mtime
     * (document.lastModified, second resolution on file://). */
    function newer(x, y) {
      if (x.b !== y.b) return x.b > y.b;
      if (x.r !== y.r) return x.r > y.r;
      return x.m > y.m;
    }
    var mine = { b: built, r: num(ROUND), m: num(Date.parse(document.lastModified)) };
    try {
      if (newer(mine, parse(localStorage.getItem(key)))) {
        localStorage.setItem(key, JSON.stringify({ b: mine.b, r: mine.r, m: mine.m }));
      }
    } catch (e) { return; }
    window.addEventListener('storage', function (ev) {
      if (ev.key !== key || !newer(parse(ev.newValue), mine)) return;
      var main = document.querySelector('.main');
      if (!main || document.getElementById('consult-stale')) return;
      var note = document.createElement('div');
      note.className = 'note warn kit-stale';
      claimId(note, 'consult-stale');
      note.setAttribute('role', 'status');
      note.appendChild(document.createTextNode(L.staleTab));
      var a = document.createElement('a');
      a.href = '#';
      a.textContent = L.staleReload;
      a.addEventListener('click', function (e) { e.preventDefault(); location.reload(); });
      note.appendChild(a);
      note.appendChild(document.createTextNode('.'));
      main.insertBefore(note, main.firstChild);
    });
  }

  function showRestoredNote(n, stale, spent) {
    var main = document.querySelector('.main');
    if (!main) return;
    var note = document.createElement('div');
    note.className = 'note';
    claimId(note, 'consult-restored');
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

  /* Answerable checks on a study page (BL-715). The recommended badge and the
   * option hints say which answer is right, so on a page that teaches and then
   * asks (`<meta name="consult-profile" content="study">`) they stay hidden
   * until the reader picks; `hidden` removes them from the accessible text
   * too, and `.kit-unanswered` drops the recommended option's tinted background. A pick shows them, plus one verdict line when the item has a
   * recommended option; Clear hides them again. The copied reply is not
   * touched: it is built from `data-label`, not from this chrome. Every other
   * page never enters here. */
  function isStudy() {
    var m = document.querySelector('meta[name="consult-profile"]');
    return !!m && m.getAttribute('content') === 'study';
  }
  function quizInputs(el) {
    return [].filter.call(el.querySelectorAll('.opts input[type="radio"], .opts input[type="checkbox"]'),
      function (i) { return !i.closest('.kit-other, .kit-notnow'); });
  }
  function updateQuiz(el) {
    if (!isStudy() || isDecided(el)) return;
    var ins = quizInputs(el);
    if (!ins.length) return;
    var picked = ins.filter(function (i) { return i.checked; });
    var on = picked.length > 0;
    var many = ins[0].type === 'checkbox';
    var rec = ins.filter(function (i) {
      var r = i.getAttribute('data-recommended');
      return r !== null && String(r).toLowerCase() !== 'no';
    });
    /* One choice: the pick is right when it is any recommended option (an open
     * item may recommend two). A set: right only when the ticked set EQUALS the
     * recommended set, so "Other" ticked beside the right set is not right. */
    var ok = false;
    if (on && rec.length) {
      if (many) {
        var other = el.querySelector('.kit-other input:checked, input[data-other]:checked');
        ok = !other && picked.length === rec.length && rec.every(function (i) { return i.checked; });
      } else {
        ok = rec.indexOf(picked[0]) > -1;
      }
    }
    el.classList.toggle('kit-unanswered', !on);
    /* A set shows the badges only once it is complete (they would give the
     * missing box away) and the hints of the ticked options only. */
    ins.forEach(function (i) {
      var lab = i.closest('label');
      if (!lab) return;
      lab.querySelectorAll('.kit-tag').forEach(function (n) { n.hidden = many ? !ok : !on; });
      lab.querySelectorAll('.hint').forEach(function (n) { n.hidden = many ? !i.checked : !on; });
    });
    var old = el.querySelector('.kit-feedback');
    if (old) old.remove();
    if (!on || !rec.length) return;
    var v = document.createElement('p');
    v.className = 'kit-feedback ' + (ok ? 'ok' : 'no');
    v.setAttribute('role', 'status');
    v.textContent = ok ? L.correct : L.notQuite;
    var opts = el.querySelector('.opts');
    opts.parentNode.insertBefore(v, opts.nextSibling);
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
        /* A gallery row asks verdict + note by default (BL-516): the injected
         * exits go inside the row's own <details> (the generator writes one),
         * or one made here for a row written by hand. */
        var host = g;
        if (isGalleryRow(el)) {
          host = g.querySelector('details.opts-more');
          if (!host) {
            host = document.createElement('details');
            host.className = 'opts-more kit-more';
            var sum = document.createElement('summary');
            sum.textContent = L.moreOptions;
            host.appendChild(sum);
            g.appendChild(host);
          }
        }
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
        host.appendChild(lab);
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
        host.appendChild(nn);
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
   * these pages is their length. Seven chips since v19, nine since v20 (BL-505:
   * `[more-examples]`; the page-defect chip became a button + box); at phone width the row
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
    [SHOW_ME, 'askShow', 'askShowTitle'],
    [MORE_EXAMPLES, 'askMore', 'askMoreTitle']
  ];
  /* The page-defect report: a button that reveals its OWN textarea, apart from
   * the answer's notes box. Clicking again hides it only while it is empty.
   * Replaces the `[page-defect]` chip (LOOP-008 Q10); older pages' bare marker
   * is still read by the session-side readers. */
  function defectBlock() {
    var wrap = document.createElement('div');
    wrap.className = 'kit-defect';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'kit-defect-btn';
    btn.textContent = L.defectBtn;
    btn.setAttribute('aria-expanded', 'false');
    var box = document.createElement('label');
    box.className = 'kit-defect-box';
    box.hidden = true;
    box.appendChild(document.createTextNode(L.defectLabel));
    var ta = document.createElement('textarea');
    ta.className = 'kit-defect-text';
    ta.rows = 3;
    box.appendChild(ta);
    btn.addEventListener('click', function () {
      if (box.hidden) { box.hidden = false; btn.setAttribute('aria-expanded', 'true'); ta.focus(); }
      else if (!ta.value.trim()) { box.hidden = true; btn.setAttribute('aria-expanded', 'false'); }
    });
    wrap.appendChild(btn);
    wrap.appendChild(box);
    return wrap;
  }
  /* A box holding text stays open (after a restore); an emptied one closes (Clear). */
  function syncDefects() {
    document.querySelectorAll('.kit-defect').forEach(function (w) {
      var box = w.querySelector('.kit-defect-box'), ta = w.querySelector('textarea');
      box.hidden = !ta.value.trim();
      w.querySelector('button').setAttribute('aria-expanded', box.hidden ? 'false' : 'true');
    });
  }

  function addAskRows() {
    items.forEach(function (el) {
      if (isDecided(el) || el.classList.contains('consult-notes')) return;
      if (el.hasAttribute('data-asks-nothing')) return;   /* a sample row asks nothing (BL-693) */
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
            /* Never the hidden kit-marks channel of a gallery row: focusing
             * it would put the cursor nowhere the reader can see. */
            var box = el.querySelector('textarea:not(.kit-marks):not(.kit-defect-text)') || el.querySelector('[contenteditable]')
                   || document.querySelector('.consult-notes textarea');
            if (box) box.focus();
          });
        }
        row.appendChild(lab);
      });
      /* After the LAST option group when there is one — below the answer, as
       * a second surface — else before the first field label, else at the end. */
      /* A gallery row folds the row into a <details>: the reader's job there
       * is a verdict and a note, and the eight chips are a second form. */
      var put = row;
      if (isGalleryRow(el)) {
        put = document.createElement('details');
        put.className = 'kit-more kit-ask-more';
        var asum = document.createElement('summary');
        asum.textContent = L.askLabel;   /* the row's own lead is hidden in CSS */
        put.appendChild(asum);
        put.appendChild(row);
      }
      var groups = el.querySelectorAll('.opts');
      var anchor = groups.length ? groups[groups.length - 1] : null;
      if (anchor) anchor.parentNode.insertBefore(put, anchor.nextSibling);
      else {
        var label = el.querySelector('.fieldlabel');
        if (label) label.parentNode.insertBefore(put, label);
        else el.appendChild(put);
      }
      /* At the END of the item, after the notes box: the item's first textarea stays
       * its notes box for every reader of the DOM (pages, tests). */
      el.appendChild(defectBlock());
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
      var folded = row && row.closest('details.kit-more');
      if (folded) row = folded;
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
      /* A proposal's checked radio is the writer's proposal: clicking it is the
       * reader confirming it, not releasing it (BL-700). */
      var it = (lab || r) && (lab || r).closest ? (lab || r).closest('.consult-item') : null;
      was = (r && r.checked && !(it && isProposal(it))) ? r : null;
    });
    document.addEventListener('click', function (ev) {
      var r = ev.target;
      if (!r || r.type !== 'radio' || r !== was) return;
      was = null;
      r.checked = false;
      r.dispatchEvent(new Event('change', { bubbles: true }));
    });
  }

  /* "Not now" stays exclusive in a CHECKBOX group too (BL-454). A radio group
   * gets that from the browser; a `select=many` group would otherwise let a
   * reader defer the question and answer it at once. So ticking not-now
   * releases every other mark of its group, and ticking any other mark releases
   * not-now. "Other" is an answer like the rest, so it combines with them.
   * Registered before the page's own change handler, which then sees the
   * settled state. */
  function exclusiveNotNow() {
    document.addEventListener('change', function (ev) {
      var t = ev.target;
      if (!t || t.type !== 'checkbox' || !t.checked) return;
      var g = t.closest ? t.closest('.opts') : null;
      if (!g) return;
      var deferring = (t.dataset.label || t.value || '') === NOT_NOW;
      g.querySelectorAll('input[type="checkbox"]:checked').forEach(function (i) {
        if (i === t) return;
        var nn = (i.dataset.label || i.value || '') === NOT_NOW;
        if (deferring || nn) i.checked = false;
      });
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
    updateQuiz(el);                   /* BL-715: study-page feedback is chrome drawn from the answer; keep before refresh() */
    syncDefects();
    redrawMarks();                    /* the marks were in a textarea: cleared too */
    // save() rebuilds the whole store from the page, so an emptied item drops
    // out of localStorage on its own — there is no per-key delete to keep in
    // step with it.
    refresh();
    save();
  }

  function addClearControls() {
    items.forEach(function (el) {
      if (isDecided(el)) return;
      if (el.hasAttribute('data-asks-nothing')) return;   /* nothing to clear on a row that asks nothing (BL-690) */
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
      var table = tw.querySelector('table');
      /* Columns of the OUTER table only: `.rows` never reaches a table nested in a cell. */
      var cols = table ? [].reduce.call(table.rows, function (m, r) { return Math.max(m, r.cells.length); }, 0) : 0;
      var tds = tw.querySelectorAll('td'), cells = tw.querySelectorAll('td, th');
      /* BL-567: a table of one to three columns must fit the screen, so the no-wrap
       * cells give way when they alone make it wider (the answer column was out of
       * sight). Four or more columns keep them and scroll, as BL-248 intends. Measured
       * again on resize, so a phone turned sideways gets its no-wrap cells back. */
      var mark = function () {
        /* BL-585: drop the previous run's break hints BEFORE measuring (they change the
         * width) and re-join the split text, so every run starts from the same DOM. */
        [].slice.call(tw.querySelectorAll('wbr.kit-slash')).forEach(function (w) { w.remove(); });
        cells.forEach(function (c) { c.normalize(); c.classList.remove('brk'); });
        tds.forEach(function (td) { td.classList.toggle('nw', td.textContent.trim().length <= 24); });
        if (cols <= 3 && tw.scrollWidth > tw.clientWidth + 1) {
          tds.forEach(function (td) { td.classList.remove('nw'); });
          /* Still wider than the screen: a word with no break point (a path) may be cut. */
          var still = tw.scrollWidth > tw.clientWidth + 1;
          if (still) cells.forEach(function (c) { c.classList.add('brk'); });
        }
        /* BL-585: the cut prefers a slash. A <wbr> after each "/" is a break opportunity that
         * `overflow-wrap: anywhere` only falls back from, so a path breaks between segments and
         * mid-segment only when one segment alone is wider than the column. <wbr> adds no text. */
        cells.forEach(function (c) {
          /* BL-604: a cell of a nested .tw inherits `anywhere` from its outer cell.brk (the
           * outer .tw is measured first), and its own box then fits: it is cut all the same.
           * Only an outer CELL counts: p, li and the rest inherit `anywhere` too, and a table
           * that fits inside them is not cut. */
          if (!c.classList.contains('brk') && !c.parentNode.closest('td.brk, th.brk')) return;
          c.classList.add('brk');
          /* A nested cell is also inside its outer cell: each text node belongs to its own cell only. */
          var walker = document.createTreeWalker(c, NodeFilter.SHOW_TEXT), t, nodes = [];
          while ((t = walker.nextNode())) {
            if (t.nodeValue.indexOf('/') !== -1 && t.parentNode.closest('td, th') === c) nodes.push(t);
          }
          nodes.forEach(function (n) {
            for (var i = n.nodeValue.length - 1; i > 0; i--) {
              if (n.nodeValue.charAt(i - 1) !== '/') continue;
              /* A date (01/10/2026) or a fraction (1/2) is not a path: digit "/" digit stays whole. */
              if (/\d/.test(n.nodeValue.charAt(i - 2)) && /\d/.test(n.nodeValue.charAt(i))) continue;
              var w = document.createElement('wbr');
              w.className = 'kit-slash';
              n.parentNode.insertBefore(w, n.splitText(i));
            }
          });
        });
        tw.classList.toggle('overflows', tw.scrollWidth > tw.clientWidth + 1);
      };
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
    /* Nothing left to answer: the narrow layout stops pinning the copy bar to the
     * viewport (`.rail.settled`, components.css, BL-575). The bar stays in the page,
     * after the content, because the notes box is still sendable. */
    var railEl = document.querySelector('.rail');
    /* Proposals still to confirm or correct are work left: the page is not
     * "all decided" and the bar stays pinned (BL-692). */
    if (railEl) railEl.classList.toggle('settled', !r.total && !r.proposals);
    /* Corrections typed on proposals count like answers (copy() counts them), but
     * apart from the questions: they are not part of the denominator. */
    var fx = r.fixed ? L.fixes(r.fixed) : '';
    if (!r.total) {
      say(r.proposals > r.fixed ? L.proposalsLeft + (fx ? ' \u00b7 ' + fx : '') : r.proposals ? fx : L.allDecided);
      return;
    }
    say(r.answered
      ? L.progress(r.answered, r.total) + (r.blank.length ? L.missing(r.blank) : '') + (fx ? ' \u00b7 ' + fx : '')
      : (fx || L.none));
  }

  function copy() {
    var r = collect();
    /* `markdown`, not `answered`: a page whose only filled box is the general
     * notes has something to send, and `answered` deliberately no longer counts
     * that box. Refusing on the counter would make the notes unsendable. */
    if (!r.markdown) {
      /* BL-587: on an all-decided page the status line says nothing is left to answer. */
      say(r.total ? L.nothingToCopy : r.proposals ? L.proposalsNothingToCopy : L.allDecidedNothingToCopy);
      return;
    }
    /* Pressing the button IS sending: from here the session has the answers,
     * and the next regeneration must not hand them back. Recorded on the
     * fallback path too — there the reader copies the pre-selected text, which
     * is the same act with a worse clipboard. */
    items.forEach(function (el) {
      var body = replyBody(el);
      if (body) copied[el.dataset.id] = fnv(body);
    });
    noteGroups().forEach(function (g) {
      if (groupNoteText(g)) copied[groupKey(g)] = fnv(groupNoteText(g));
    });
    save();
    var msg = L.copied(r.answered + r.fixed) + (r.blank.length ? L.blankList(r.blank) : L.noneBlank);

    function fallback() {
      var ta = document.createElement('textarea');
      ta.value = r.markdown;
      ta.setAttribute('aria-label', L.copy);   /* BL-706: the one textarea the composer renders that the reader sees */
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
    claimId(b, 'kit-theme');
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
    /* In `.page`, where components.css pins it to the top band; never fixed over
     * the reading column again (render-probe `fixed-over-text`, 18 of 18 A/B
     * pages, 2026-09-25). A page without `.page` gets it at the end of <body>. */
    var host = document.querySelector('.page');
    if (host) host.insertBefore(b, host.firstChild);
    else document.body.appendChild(b);
  }

  /* ---- The gallery row: zoom, keyboard, filters (kit v21) ----------------
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
  /* Set by gallery() once its rows exist; called after restore() and by the
   * per-item Clear, the two writers of a marks textarea that are not the
   * mark layer itself. */
  var redrawMarks = function () {};

  /* A closed <details> of extra options never hides a mark the reader made:
   * a restored or ticked input inside one opens it (it is never closed here). */
  function openFilledMore() {
    [].forEach.call(document.querySelectorAll('details.opts-more, details.kit-more'), function (d) {
      if (d.querySelector('input:checked')) d.open = true;
    });
  }

  /* By SHAPE, like the checker (`gallery_findings`): the rows written by hand
   * before the generator existed carry the grid and not the class, and a
   * predicate that knew only the class would go silent on exactly them. */
  function isGalleryRow(el) {
    return el.classList.contains('consult-gallery')
        || !!el.querySelector('.gal:not(.shots), figure[data-tile]');
  }

  /* A consult item with several raster images renders them as `.gal.shots`
   * (BL-493): the same grid and the same zoom dialog, in a reduced mode — no
   * compare, no marks, no row walk — and NOT a gallery row: the item keeps its
   * own question and options. */
  function shotFigures(fig) {
    var grid = fig.closest('.gal.shots');
    /* BL-597/626: a lone figure of an item (`data-viewer`, written by the
     * builder) is a walk of one; a run of figures, svg ones included, is the
     * grid's. */
    return grid ? [].filter.call(grid.querySelectorAll('figure'), hasPicture)
      : fig.hasAttribute('data-viewer') && hasPicture(fig) ? [fig] : [];
  }
  function hasPicture(f) { return !!f.querySelector('img, svg'); }

  /* The declared matrix is the keyboard order — the same list the checker
   * judges completeness against, so the arrows and the rule agree on what the
   * row's cells are: a states row's own `data-states`, else the block's
   * `data-tiles`. A row with neither falls back to the order its own figures
   * are written in. */
  function tileOrder(row) {
    var own = (row.getAttribute('data-states') || '').split(/\s+/).filter(Boolean);
    if (own.length) return own;
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
    /* The checker strips a tile name; the arrows (indexOf) and the CSS filters
     * (^= and $=) compare it exactly, so the stray space goes here, once. */
    rows.forEach(function (row) {
      row.querySelectorAll('figure[data-tile]').forEach(function (f) {
        f.setAttribute('data-tile', f.getAttribute('data-tile').trim());
      });
    });
    /* Up/Down skips settled rows: collapseDecided has folded them away, and
     * the kit's contract is that the open questions stay in view. */
    var walkRows = rows.filter(function (r) { return !isDecided(r); });
    var groups = [].slice.call(document.querySelectorAll('.consult-group'))
      .filter(function (g) { return (g.getAttribute('data-tiles') || '').trim(); });
    var shots = [].slice.call(document.querySelectorAll(
      '.consult-item .gal.shots figure, .consult-item figure[data-viewer]')).filter(hasPicture);
    if (!rows.length && !groups.length && !shots.length) return;

    /* ---- the dialog ---- */
    var dlg = document.createElement('dialog');
    dlg.className = 'kit-zoom';
    dlg.tabIndex = -1;                /* focusable, so compare() can park the focus here */
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
    /* Compare: the other mode of the same viewport, GitHub's three image-diff
     * modes (research note, pattern 2). Buttons and one range input, all in
     * the dialog — outside every item, so `readItem` never sees the slider. */
    var hWith = document.createElement('span');
    hWith.className = 'kit-zoom-with';
    var cmpWrap = document.createElement('span');
    cmpWrap.className = 'kit-zoom-cmpgroup';
    var cmpLab = document.createElement('span');
    cmpLab.className = 'kit-gallabel';
    cmpLab.textContent = L.cmp;
    cmpWrap.appendChild(cmpLab);
    var cmpBtns = [['off', 'cmpOff'], ['2up', 'cmp2up'], ['swipe', 'cmpSwipe'], ['onion', 'cmpOnion']]
      .map(function (c) {
        var b = document.createElement('button');
        b.type = 'button';
        b.className = 'kit-zoom-cmp';
        b.dataset.value = c[0];
        b.textContent = L[c[1]];
        b.addEventListener('click', function () { cmp = c[0]; compare(); });
        cmpWrap.appendChild(b);
        return b;
      });
    var range = document.createElement('input');
    range.type = 'range';
    range.className = 'kit-zoom-range';
    range.min = '0';
    range.max = '100';
    range.title = L.cmpRange;
    range.setAttribute('aria-label', L.cmpRange);
    cmpWrap.appendChild(range);
    /* Marks from the keyboard: this button drafts a region, the arrows shape
     * it. It sits in the tools group because it takes the range's place — the
     * range shows only with compare on, the button only with it off. */
    var bMark = document.createElement('button');
    bMark.type = 'button';
    bMark.className = 'kit-zoom-mark';
    bMark.textContent = L.markAdd;
    bMark.title = L.markAddTitle;
    cmpWrap.appendChild(bMark);
    /* The item's images, one at a time: visible previous/next beside the keys
     * and the swipe (BL-597). Shown only in that mode, only for 2+ images. */
    var nav = document.createElement('span');
    nav.className = 'kit-zoom-nav';
    var bPrev = document.createElement('button');
    bPrev.type = 'button';
    bPrev.className = 'kit-zoom-prev';
    bPrev.textContent = '\u2039 ' + L.zoomPrev;
    var bNext = document.createElement('button');
    bNext.type = 'button';
    bNext.className = 'kit-zoom-next';
    bNext.textContent = L.zoomNext + ' \u203a';
    nav.appendChild(bPrev);
    nav.appendChild(bNext);
    head.appendChild(hRow);
    head.appendChild(hTile);
    head.appendChild(nav);
    head.appendChild(hWith);
    head.appendChild(hCell);
    head.appendChild(cmpWrap);
    head.appendChild(bSize);
    head.appendChild(bClose);
    var note = document.createElement('p');
    note.className = 'kit-zoom-note';
    note.hidden = true;
    var body = document.createElement('div');
    body.className = 'kit-zoom-body';
    var stack = document.createElement('div');
    stack.className = 'kit-compare';
    var img = document.createElement('img');
    var other = document.createElement('img');   /* the sibling, on top */
    other.className = 'kit-zoom-other';
    stack.appendChild(img);
    stack.appendChild(other);
    /* The region-mark layer: sized over the current image by placeOver(),
     * never over the sibling, and hidden by components.css whenever compare
     * is on — marks belong to the tile being judged. */
    var hl = document.createElement('div');   /* the row's highlight outline (BL-596) */
    hl.className = 'kit-hl-layer';
    hl.setAttribute('aria-hidden', 'true');
    stack.appendChild(hl);
    var mlayer = document.createElement('div');
    mlayer.className = 'kit-marks-layer';
    mlayer.title = L.markHint;
    stack.appendChild(mlayer);
    /* The swipe handle: a line where the two captures meet. Placed over the
     * current image like the mark layer (the image, not the stack, is what
     * the clip's percentage is of) and drawn by components.css at
     * --kit-swipe, so the slider moves it with no code of its own. */
    var hlayer = document.createElement('div');
    hlayer.className = 'kit-swipe-layer';
    var handle = document.createElement('div');
    handle.className = 'kit-swipe-handle';
    hlayer.appendChild(handle);
    stack.appendChild(hlayer);
    /* A figure that is an inline svg is shown as that svg (a clone: it keeps
     * the page's CSS and currentColor, which an img element would lose; the
     * kit's accent classes are scoped to `.kit-zoom-svg` in components.css)
     * at the size it was drawn (BL-626). */
    var svgBox = document.createElement('div');
    svgBox.className = 'kit-zoom-svg';
    stack.appendChild(svgBox);
    /* The scroller of a drawing wider than the dialog (the caption stays out of
     * it). Focusable in svg mode so the keyboard can pan it. */
    body.appendChild(stack);
    var cap = document.createElement('p');   /* the figure's title, per image */
    cap.className = 'kit-zoom-cap';
    body.appendChild(cap);
    var keys = document.createElement('p');
    keys.className = 'kit-zoom-keys';
    keys.textContent = L.zoomKeys;
    dlg.appendChild(head);
    dlg.appendChild(note);
    dlg.appendChild(body);
    dlg.appendChild(keys);
    document.body.appendChild(dlg);

    var origin = null;                /* the figure that opened it: focus returns here */
    var opener = null;                /* the figure on screen now */
    var cmp = 'off';                  /* the compare mode the reader chose */
    var sib = null;                   /* the opener's other-mode figure, if any */

    /* Ampliar is for seeing the drawing bigger (BL-712): Fit when the dialog
     * holds it wider than drawn, else the drawn size (scaled down to the
     * window its text would shrink below what the page already showed; the
     * dialog scrolls). A tie keeps the drawn size. Measured, so it runs with
     * the dialog open; no drawn size (no viewBox, no width) stays at Fit. */
    function svgSize() {
      var w = parseFloat(svgBox.style.getPropertyValue('--kit-svg-w'));
      dlg.classList.remove('native');
      if (w > 0 && svgBox.firstChild.getBoundingClientRect().width <= w + 0.5) dlg.classList.add('native');
    }

    function sizeLabel() {
      // Names the DESTINATION, like the theme button does.
      bSize.textContent = dlg.classList.contains('native') ? L.zoomFit : L.zoomNative;
      bSize.setAttribute('aria-pressed', dlg.classList.contains('native') ? 'true' : 'false');
    }

    /* A fresh open, or a change of kind (capture <-> drawing): back to the top
     * left. A step between images of one kind keeps the reader's vertical place
     * (a tall capture read at 1:1); each new image still starts at the left. */
    function resetScroll() {
      stack.scrollLeft = 0; stack.scrollTop = 0; body.scrollTop = 0; dlg.scrollTop = 0;
    }

    /* A drawing (or a capture at 1:1) wider than the viewer pans by touch; one
     * that fits has nothing to pan, so a horizontal swipe is the walk. The class
     * decides components.css's touch-action, which is what lets the browser
     * deliver the swipe's pointerup instead of cancelling the pointer. */
    function syncPan() {
      dlg.classList.toggle('pan', dlg.classList.contains('native') && stack.scrollWidth > stack.clientWidth + 1);
      /* The hint offers a swipe only where a swipe walks. */
      if (!draft && dlg.classList.contains('shots') && !keys.hidden)
        keys.textContent = dlg.classList.contains('pan') ? L.zoomKeysPan : L.zoomKeysShots;
    }
    /* The scroller is Tab-focusable while it overflows (Chrome); when it stops
     * overflowing the focus would fall to the body and the arrows with it. */
    function keepFocus() { if (document.activeElement === stack) dlg.focus(); }
    window.addEventListener('resize', function () { keepFocus(); syncPan(); });

    function show(fig) {
      keepFocus();
      var row = fig.closest('.consult-item');
      var src = fig.querySelector('img');
      var svg = src ? null : fig.querySelector('svg');
      opener = fig;
      img.setAttribute('src', src ? src.getAttribute('src') : '');
      img.setAttribute('alt', src ? (src.getAttribute('alt') || '') : '');
      svgBox.textContent = '';
      svgBox.style.removeProperty('--kit-svg-w');
      var c = null;
      if (svg) {
        c = svg.cloneNode(true);
        var vb = (svg.getAttribute('viewBox') || '').trim().split(/[\s,]+/);
        var vw = vb.length === 4 ? parseFloat(vb[2]) : 0;
        /* No viewBox: the width attribute, when it is a plain number; with
         * neither there is no drawn size, and the drawing stays at Fit. */
        if (!(vw > 0) && /^\s*\d+(\.\d+)?(px)?\s*$/.test(svg.getAttribute('width') || '')) vw = parseFloat(svg.getAttribute('width'));
        if (vw > 0) svgBox.style.setProperty('--kit-svg-w', vw + 'px');   /* the svg inherits it */
        svgBox.appendChild(c);
      }
      /* Each kind has its own default size: a capture fits the window, a
       * drawing shows at the larger of Fit and its drawn size (svgSize), each
       * drawing its own (a tall one after a wide one would otherwise keep a
       * Fit that shrinks its text). A change of kind resets it; walking
       * capture to capture keeps the reader's size. */
      var changed = !!svg !== dlg.classList.contains('svgmode');
      if (changed) dlg.classList.remove('native');
      dlg.classList.toggle('svgmode', !!svg);
      if (svg && dlg.open) svgSize();
      if (changed) resetScroll(); else stack.scrollLeft = 0;
      sizeLabel();
      hRow.textContent = (row && (row.dataset.heading || row.dataset.title)) || '';
      hRow.title = hRow.textContent;      /* a narrow header truncates it */
      /* The tile's highlight, copied as drawn (percentages of the capture). */
      hl.textContent = '';
      var hs = fig.querySelector('.gal-hl-layer');
      if (hs) [].forEach.call(hs.children, function (c) { hl.appendChild(c.cloneNode(true)); });
      cancelDraft();
      var set = shotFigures(fig);
      dlg.classList.toggle('shots', set.length > 0);
      dlg.classList.toggle('multi', set.length > 1);   /* a stable width: the buttons stay where they are */
      hTile.hidden = set.length === 1;      /* "1 / 1" counts nothing */
      keys.hidden = set.length === 1;       /* nor is there a walk to explain */
      hTile.textContent = set.length ? (set.indexOf(fig) + 1) + ' / ' + set.length
        : fig.getAttribute('data-tile') || '';
      hCell.textContent = (row && row.dataset.id) || '';
      if (!draft) keys.textContent = set.length ? L.zoomKeysShots : L.zoomKeys;
      var capEl = set.length ? fig.querySelector('figcaption') : null;
      cap.textContent = capEl ? capEl.textContent.trim() : '';
      cap.hidden = !cap.textContent;
      nav.hidden = set.length < 2;
      var at = set.indexOf(fig);
      /* A disabled control drops the focus to the body, outside the dialog,
       * and the arrows die with it (as in compare()). */
      if ((at === 0 && document.activeElement === bPrev)
          || (at === set.length - 1 && document.activeElement === bNext)) dlg.focus();
      bPrev.disabled = at <= 0;
      bNext.disabled = at === set.length - 1;
      sib = sibling(fig);
      var sImg = sib && sib.querySelector('img');
      if (sImg) other.setAttribute('src', sImg.getAttribute('src'));
      else other.removeAttribute('src');
      other.setAttribute('alt', sImg ? (sImg.getAttribute('alt') || '') : '');
      compare();
      drawDialog();
      syncPan();
    }

    /* The tile to compare against, looked up among ALL the row's figures (a
     * filter hides tiles, not data): on a review row the other half of the
     * before/after pair, on a matrix row the other mode of the same viewport
     * (`light-desktop` <-> `dark-desktop`). */
    var PAIR = { before: 'after', after: 'before' };
    function sibling(fig) {
      var name = fig.getAttribute('data-tile') || '';
      var m = /^(light|dark)-/.exec(name);
      var other = PAIR.hasOwnProperty(name) ? PAIR[name]
        : m ? (m[1] === 'light' ? 'dark-' : 'light-') + name.slice(m[0].length)
        : null;
      if (!other) return null;
      var f = tileFigure(fig.closest('.consult-item'), other);
      return f && f.querySelector('img') ? f : null;
    }

    /* Swipe and onion stack one image on the other, which is only honest when
     * both are the same size. They come from one viewport, so they should be;
     * when they are not, the dialog shows them side by side and says so. The
     * check runs again on every `load`, because a capture not yet decoded has
     * no size to compare. */
    function compare() {
      var on = !!sib && cmp !== 'off';
      var differ = on && cmp !== '2up' && img.complete && other.complete
        && img.naturalWidth > 0 && other.naturalWidth > 0
        && (img.naturalWidth !== other.naturalWidth || img.naturalHeight !== other.naturalHeight);
      dlg.setAttribute('data-compare', !on ? 'off' : differ ? '2up' : cmp);
      note.hidden = !differ;
      note.textContent = differ ? L.cmpSize(img.naturalWidth + 'x' + img.naturalHeight,
        other.naturalWidth + 'x' + other.naturalHeight) : '';
      hWith.textContent = on ? '\u2194 ' + sib.getAttribute('data-tile') : '';
      if (on) cancelDraft();          /* marks are drawn with compare off */
      placeOver(hlayer, img); placeOver(hl, img);
      /* A disabled control loses the focus to the body, outside the dialog,
       * and the arrows die with it: park the focus on the dialog first. */
      if (!sib && cmpBtns.indexOf(document.activeElement) !== -1) dlg.focus();
      cmpBtns.forEach(function (b) {
        b.disabled = !sib;
        b.title = sib ? L.cmpTitle : L.cmpNone;
        b.setAttribute('aria-pressed', b.dataset.value === (sib ? cmp : 'off') ? 'true' : 'false');
      });
    }
    img.addEventListener('load', compare);
    other.addEventListener('load', compare);

    /* The slider is the CURRENT tile's share in both modes: in swipe it shows
     * left of the line, in onion the sibling on top fades out as it grows. So
     * right always means more of the tile being judged. Never stored. */
    function slide() {
      dlg.style.setProperty('--kit-swipe', range.value + '%');
      dlg.style.setProperty('--kit-onion', String(1 - range.value / 100));
    }
    /* Stopped here: the composer's document listeners would refresh() the
     * status line on every tick and wipe a copy confirmation. */
    range.addEventListener('input', function (ev) { ev.stopPropagation(); slide(); });
    range.addEventListener('change', function (ev) { ev.stopPropagation(); });

    function open(fig) {
      /* The image's own default size on every fresh open (a capture fits the
       * window, a drawing opens at its drawn size; show() sets it): the reader
       * asked to see this image, not to resume the last one's magnification.
       * Moving with the arrows between images of one kind keeps whatever size
       * is on screen — there it IS the same look, continued. */
      dlg.classList.remove('native', 'svgmode');
      sizeLabel();
      /* Compare too: off, the slider in the middle. The arrows keep both,
       * like the size — moving on is the same look, continued. */
      cmp = 'off';
      range.value = '50';
      slide();
      origin = fig;
      show(fig);
      /* showModal() focuses the first header control, a compare button; the
       * size button is the one a fresh open has always handed the focus to. */
      if (dlg.showModal) { dlg.showModal(); bSize.focus(); }
      else dlg.setAttribute('open', '');   /* no modal support: still readable */
      if (dlg.classList.contains('svgmode')) { svgSize(); sizeLabel(); }
      resetScroll();                       /* the layout of the last open survives a close */
      /* show() ran while the dialog was closed, when the image had no box. */
      placeOver(mlayer, img);
      placeOver(hlayer, img); placeOver(hl, img);
      syncPan();
    }

    bSize.addEventListener('click', function () {
      dlg.classList.toggle('native');
      sizeLabel();
      syncPan();
    });
    bClose.addEventListener('click', function () { dlg.close(); });
    bPrev.addEventListener('click', function () { step(-1); });
    bNext.addEventListener('click', function () { step(1); });
    /* Esc closes without a listener of its own; `close` fires for both paths,
     * so the focus return is written once. */
    dlg.addEventListener('close', function () {
      cancelDraft();
      /* An item's images: the one shown. A gallery row: the tile that opened it. */
      var back = dlg.classList.contains('shots') && opener && document.contains(opener) ? opener : origin;
      if (back) back.focus();
    });

    /* The tiles, in the order the matrix declares. A tile the row does not
     * carry is stepped OVER rather than treated as the end: a row missing a
     * cell is a defect the checker reports, and the arrows must not turn it
     * into a wall. Filters never enter here — hiding a tile is a viewing aid,
     * and a reader who navigates to a hidden cell still has to be able to
     * judge it. */
    function step(dir) {
      if (!opener) return;
      var set = shotFigures(opener);
      if (set.length) {                 /* an item's images: its own order, no wrapping */
        var at = set.indexOf(opener) + dir;
        if (set[at]) show(set[at]);
        return;
      }
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
      if (!opener || shotFigures(opener).length) return;   /* no rows in this mode */
      var row = opener.closest('.consult-item');
      var name = opener.getAttribute('data-tile');
      var i = walkRows.indexOf(row);
      if (i === -1) return;
      for (var j = i + dir; j >= 0 && j < walkRows.length; j += dir) {
        var f = tileFigure(walkRows[j], name);
        if (f) return show(f);
      }
    }

    dlg.addEventListener('keydown', function (ev) {
      /* A region being drafted owns the arrows, Enter and Esc: moving it is
       * what the reader is doing, and Esc drops the draft, not the dialog. */
      if (draft) {
        if (/^Arrow/.test(ev.key)) { ev.preventDefault(); nudge(ev.key, ev.shiftKey); return; }
        /* Enter on a focused dialog button (Close, the size toggle, a compare
         * mode) presses that button, as it does everywhere else; only Enter
         * on the dialog itself — where startDraft parks the focus — saves. */
        if (ev.key === 'Enter' && ev.target === dlg) { ev.preventDefault(); commitDraft(); return; }
        if (ev.key === 'Escape') { ev.preventDefault(); cancelDraft(); return; }
      }
      var moves = { ArrowLeft: [step, -1], ArrowRight: [step, 1],
                    ArrowUp: [stepRow, -1], ArrowDown: [stepRow, 1] };
      var m = moves[ev.key];
      /* A focused slider owns the arrows, as every native range does; the
       * walk is one Tab away. */
      if (!m || ev.target === range) return;
      /* An item's images have no rows: Up/Down scroll a tall capture. */
      if (m[0] === stepRow && dlg.classList.contains('shots')) return;
      ev.preventDefault();            /* or the dialog scrolls under the move */
      m[0](m[1]);
    });

    /* ---- region marks (Phase 4) ----
     *
     * A rectangle dragged on the dialog image, kept as PERCENTAGES of the image
     * (research note, pattern 3: pins relative to the frame), so a mark drawn
     * at fit size lands on the same pixels at native size and on a grid tile of
     * any width.
     *
     * Storage is ONE hidden `textarea.kit-marks` per tiled row, the
     * last textarea of the item, holding one contract line per mark:
     *   [mark light-desktop 12.5,34.0 40.0x10.5] the breadcrumb wraps
     * It is not a second store: readItem pastes it, snapshotItem/restore keep
     * it (the `a` list, after the notes box, so a stored notes answer keeps its
     * index), the question-hash rule and the round rule govern it like any
     * answer, Clear empties it. The checker does not count it as a notes box.
     *
     * Drawing needs an open row and compare off; a decided row shows its marks
     * (a page may carry them in its own kit-marks textarea) and draws none.
     * Neither does an item's images (shots mode, BL-493): its figures carry no
     * tile, so a mark there could never be redrawn or opened (BL-655). */
    var MARK_LINE = /^\[mark (\S+) (\d{1,3}(?:\.\d)?),(\d{1,3}(?:\.\d)?) (\d{1,3}(?:\.\d)?)x(\d{1,3}(?:\.\d)?)\](?: (.*))?$/;

    function marksBox(row) { return row.querySelector('textarea.kit-marks'); }

    /* ---- the keyboard draft ----
     * The Mark button puts a 20 x 20 region in the middle of the image;
     * arrows move it one percent, Shift+arrows grow or shrink it one percent,
     * both clamped inside the image and never under the 1 % the pointer path
     * also refuses. Enter hands it to the same note dialog a drag does. */
    var draft = null;                 /* { row, tile, box, x, y, w, h } */
    function clampTo(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }
    function drawDraft() {
      draft.box.style.left = draft.x + '%';
      draft.box.style.top = draft.y + '%';
      draft.box.style.width = draft.w + '%';
      draft.box.style.height = draft.h + '%';
    }
    function canMark(row) {
      return !!row && !isDecided(row) && !!marksBox(row) && !dlg.classList.contains('shots')
        && dlg.getAttribute('data-compare') === 'off';
    }
    function startDraft() {
      if (!opener || pending || drag) return;
      var row = opener.closest('.consult-item');
      if (!canMark(row)) return;
      cancelDraft();
      var box = document.createElement('div');
      box.className = 'kit-mark drawing';
      mlayer.appendChild(box);
      draft = { row: row, tile: opener.getAttribute('data-tile'), box: box, x: 40, y: 40, w: 20, h: 20 };
      drawDraft();
      keys.textContent = L.markKeys;
      dlg.focus();                    /* the arrows reach the dialog, not a button */
    }
    function cancelDraft() {
      if (!draft) return;
      draft.box.remove();
      draft = null;
      keys.textContent = L.zoomKeys;
    }
    function nudge(key, resize) {
      var dx = key === 'ArrowLeft' ? -1 : key === 'ArrowRight' ? 1 : 0;
      var dy = key === 'ArrowUp' ? -1 : key === 'ArrowDown' ? 1 : 0;
      if (resize) {
        draft.w = clampTo(draft.w + dx, 1, 100 - draft.x);
        draft.h = clampTo(draft.h + dy, 1, 100 - draft.y);
      } else {
        draft.x = clampTo(draft.x + dx, 0, 100 - draft.w);
        draft.y = clampTo(draft.y + dy, 0, 100 - draft.h);
      }
      drawDraft();
    }
    function commitDraft() {
      var d = draft;
      draft = null;
      keys.textContent = L.zoomKeys;
      openNote({ row: d.row, index: null, box: d.box,
                 mark: { tile: d.tile, x: d.x, y: d.y, w: d.w, h: d.h, note: '' } });
    }
    bMark.addEventListener('click', startDraft);
    /* A real Esc never reaches here during a draft: the keydown above cancels
     * it, and a cancelled keydown starts no close request (test-gallery-keys.sh
     * proves it with a trusted key). This covers a close request that arrives
     * with no keydown the page sees. */
    dlg.addEventListener('cancel', function (ev) {
      if (draft) { ev.preventDefault(); cancelDraft(); }
    });

    function readMarks(row) {
      var ta = marksBox(row);
      if (!ta) return [];
      return ta.value.split('\n').map(function (l) {
        var m = MARK_LINE.exec(l.trim());
        return m ? { n: 0, tile: m[1], x: +m[2], y: +m[3], w: +m[4], h: +m[5], note: m[6] || '' } : null;
      }).filter(Boolean).map(function (k, i) { k.n = i + 1; return k; });
    }

    function markLine(k) {
      return '[mark ' + k.tile + ' ' + k.x.toFixed(1) + ',' + k.y.toFixed(1) + ' '
        + k.w.toFixed(1) + 'x' + k.h.toFixed(1) + ']' + (k.note ? ' ' + k.note : '');
    }

    /* Written like a reader's typing: the composer's input listener refreshes
     * the count and saves the store, so no second path can drift from it. */
    function writeMarks(row, marks) {
      var ta = marksBox(row);
      ta.value = marks.map(markLine).join('\n');
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      drawRow(row);
      drawDialog();
    }

    function drawBoxes(layer, marks) {
      [].slice.call(layer.querySelectorAll('.kit-mark:not(.drawing)')).forEach(function (b) { b.remove(); });
      marks.forEach(function (k) {
        var b = document.createElement('div');
        b.className = 'kit-mark';
        b.style.left = k.x + '%';
        b.style.top = k.y + '%';
        b.style.width = k.w + '%';
        b.style.height = k.h + '%';
        if (k.note) b.title = k.note;   /* an attribute, never text: the hash reads text */
        b.setAttribute('data-n', k.n);  /* components.css draws it: the number locates the note in the row's list */
        layer.appendChild(b);
      });
    }

    /* Over the image's CONTENT box: the grid tile has a border, the dialog
     * image a centring margin, and a layer sized to the parent would put a
     * percentage on the wrong pixels. */
    function placeOver(layer, im) {
      layer.style.left = (im.offsetLeft + im.clientLeft) + 'px';
      layer.style.top = (im.offsetTop + im.clientTop) + 'px';
      layer.style.width = im.clientWidth + 'px';
      layer.style.height = im.clientHeight + 'px';
    }

    function placeTile(fig) {
      var layer = fig.querySelector('.kit-marks-tile'), im = fig.querySelector('img');
      if (layer && im) placeOver(layer, im);
    }

    var ro = window.ResizeObserver ? new ResizeObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.target === img || e.target === stack) { placeOver(mlayer, img); placeOver(hlayer, img); placeOver(hl, img); }
        else placeTile(e.target.closest('figure') || e.target);
      });
    }) : null;
    if (ro) { ro.observe(img); ro.observe(stack); }

    /* The row's visible list of region notes. Built here, so a page with
     * scripts off gains no markup. Spans and buttons only: it is chrome
     * (questionHash drops it) and never a field readItem could paste, so a
     * note reaches the reply once, from the hidden textarea. */
    function drawList(row, marks) {
      var box = row.querySelector('.kit-marks-list');
      if (!marksBox(row) || (isDecided(row) && !marks.length)) { if (box) box.remove(); return; }
      if (!box) {
        box = document.createElement('div');
        box.className = 'kit-marks-list';
        var anchor = row.querySelector('figure[data-tile]');
        if (anchor && anchor.parentNode) anchor.parentNode.insertAdjacentElement('afterend', box);
        else row.appendChild(box);
      }
      box.textContent = '';
      var h = document.createElement('p');
      h.className = 'kit-marks-title';
      h.textContent = L.marksTitle;
      box.appendChild(h);
      if (!marks.length) {
        var e = document.createElement('p');
        e.className = 'kit-marks-empty';
        e.textContent = L.marksEmpty;
        box.appendChild(e);
        return;
      }
      var ol = document.createElement('ol');
      marks.forEach(function (k) {
        var li = document.createElement('li');
        li.setAttribute('data-n', k.n);
        var go = document.createElement('button');
        go.type = 'button';
        go.className = 'kit-marks-go';
        go.title = L.marksOpen;
        var num = document.createElement('b');
        num.textContent = k.n + '.';
        var tile = document.createElement('span');
        tile.className = 'kit-marks-tile-name';
        tile.textContent = k.tile;
        var note = document.createElement('span');
        note.className = 'kit-marks-text';
        note.textContent = k.note || L.marksNoNote;
        [num, tile, note].forEach(function (n) { go.appendChild(n); });
        go.addEventListener('click', function () { openMark(row, k); });
        li.appendChild(go);
        if (!isDecided(row)) {
          var rm = document.createElement('button');
          rm.type = 'button';
          rm.className = 'kit-marks-rm';
          rm.textContent = L.marksRemove;
          rm.addEventListener('click', function () {
            var cur = readMarks(row);
            cur.splice(k.n - 1, 1);
            writeMarks(row, cur);
          });
          li.appendChild(rm);
        }
        ol.appendChild(li);
      });
      box.appendChild(ol);
    }

    /* The zoom on the mark's tile, that mark outlined. */
    function openMark(row, k) {
      var fig = row.querySelector('figure[data-tile="' + k.tile + '"]');
      if (!fig) return;
      open(fig);
      var b = mlayer.querySelector('.kit-mark[data-n="' + k.n + '"]');
      if (b) b.classList.add('hot');
    }

    function drawRow(row) {
      var marks = readMarks(row);
      drawList(row, marks);
      row.querySelectorAll('figure[data-tile]').forEach(function (fig) {
        var mine = marks.filter(function (k) { return k.tile === fig.getAttribute('data-tile'); });
        var layer = fig.querySelector('.kit-marks-tile');
        if (!mine.length) { if (layer) layer.remove(); return; }
        if (!layer) {
          layer = document.createElement('div');
          layer.className = 'kit-marks-tile';
          fig.appendChild(layer);
          var im = fig.querySelector('img');
          if (ro) { ro.observe(fig); if (im) ro.observe(im); }
        }
        drawBoxes(layer, mine);
        placeTile(fig);
      });
    }

    function drawDialog() {
      if (!opener) return;
      var row = opener.closest('.consult-item');
      var tile = opener.getAttribute('data-tile');
      /* Parked first: a disabled button drops the focus out of the dialog. */
      var noMark = isDecided(row) || !marksBox(row) || dlg.classList.contains('shots');
      mlayer.classList.toggle('readonly', noMark);
      if (noMark && document.activeElement === bMark) dlg.focus();
      bMark.disabled = noMark;
      drawBoxes(mlayer, readMarks(row).filter(function (k) { return k.tile === tile; }));
      placeOver(mlayer, img);
    }

    rows.forEach(function (row) {
      /* A sample row asks nothing (BL-693): no mark-mode box, so no way to answer on it. */
      if (row.hasAttribute('data-asks-nothing') || marksBox(row) || !row.querySelector('figure[data-tile] img')) return;
      var ta = document.createElement('textarea');
      ta.className = 'kit-marks';
      ta.hidden = true;
      row.appendChild(ta);
    });
    redrawMarks = function () { rows.forEach(drawRow); };

    /* The note dialog: a second, small modal, a sibling of the zoom dialog
     * rather than inside it, so its text box keeps the arrow keys (the zoom
     * dialog walks tiles on them) and its close cannot reach the zoom
     * dialog's focus return. Buttons act synchronously; Esc is a cancel. */
    var ndlg = document.createElement('dialog');
    ndlg.className = 'kit-mark-note';
    var nlab = document.createElement('label');
    nlab.textContent = L.markNote;
    var ninput = document.createElement('input');
    ninput.type = 'text';
    nlab.appendChild(ninput);
    ndlg.appendChild(nlab);
    var nrow = document.createElement('div');
    nrow.className = 'kit-mark-acts';
    var nbtn = {};
    [['save', 'markSave'], ['delete', 'markDelete'], ['cancel', 'markCancel']].forEach(function (a) {
      var b = document.createElement('button');
      b.type = 'button';
      b.dataset.act = a[0];
      b.textContent = L[a[1]];
      b.addEventListener('click', function () { finish(a[0]); });
      nrow.appendChild(b);
      nbtn[a[0]] = b;
    });
    ndlg.appendChild(nrow);
    document.body.appendChild(ndlg);
    /* Not an answer until saved: kept from the composer's document listeners. */
    ['input', 'change'].forEach(function (t) {
      ndlg.addEventListener(t, function (ev) { ev.stopPropagation(); });
    });
    ninput.addEventListener('keydown', function (ev) {
      if (ev.key !== 'Enter') return;
      ev.preventDefault();
      finish('save');
    });
    ndlg.addEventListener('close', function () { finish('cancel'); });

    var pending = null;               /* { row, index (null = new), mark, box } */
    function openNote(p) {
      pending = p;
      ninput.value = p.mark.note;
      nbtn['delete'].hidden = p.index === null;   /* a new mark is discarded by Cancel */
      if (ndlg.showModal) ndlg.showModal(); else ndlg.setAttribute('open', '');
      ninput.focus();
    }

    function finish(act) {
      var p = pending;
      pending = null;
      if (!p) return;
      if (p.box) p.box.remove();
      var marks = readMarks(p.row);
      if (act === 'save') {
        p.mark.note = ninput.value.replace(/\s+/g, ' ').trim();
        if (p.index === null) marks.push(p.mark); else marks[p.index] = p.mark;
        writeMarks(p.row, marks);
      } else if (act === 'delete' && p.index !== null) {
        marks.splice(p.index, 1);
        writeMarks(p.row, marks);
      }
      if (ndlg.open) ndlg.close();
      /* Back into the zoom dialog, or the arrows stop walking. */
      if (dlg.open && !dlg.contains(document.activeElement)) dlg.focus();
    }

    function pct(v, from, len) { return Math.min(100, Math.max(0, (v - from) / len * 100)); }

    var drag = null;
    mlayer.addEventListener('pointerdown', function (ev) {
      /* Only a primary pointer draws: a second finger neither starts a box
       * nor takes over the first one's (BL-649). */
      if (ev.button !== 0 || !ev.isPrimary || !opener || pending) return;
      if (drag) { drag.box.remove(); drag = null; }   /* a drag whose up never came */
      cancelDraft();
      var row = opener.closest('.consult-item');
      if (!canMark(row)) return;
      ev.preventDefault();
      try { mlayer.setPointerCapture(ev.pointerId); } catch (e) { /* synthetic pointer */ }
      var box = document.createElement('div');
      box.className = 'kit-mark drawing';
      mlayer.appendChild(box);
      drag = { id: ev.pointerId, x: ev.clientX, y: ev.clientY, box: box, row: row, tile: opener.getAttribute('data-tile') };
    });

    function rectOf(d, ev) {
      var r = mlayer.getBoundingClientRect();
      if (!r.width || !r.height) return null;
      /* Endpoints rounded to tenths, the size taken between them: x + w can
       * never pass 100 by a rounding step. */
      var x0 = Math.round(pct(Math.min(d.x, ev.clientX), r.left, r.width) * 10);
      var x1 = Math.round(pct(Math.max(d.x, ev.clientX), r.left, r.width) * 10);
      var y0 = Math.round(pct(Math.min(d.y, ev.clientY), r.top, r.height) * 10);
      var y1 = Math.round(pct(Math.max(d.y, ev.clientY), r.top, r.height) * 10);
      return { tile: d.tile, x: x0 / 10, y: y0 / 10, w: (x1 - x0) / 10, h: (y1 - y0) / 10, note: '' };
    }

    mlayer.addEventListener('pointermove', function (ev) {
      if (!drag || ev.pointerId !== drag.id) return;
      var k = rectOf(drag, ev);
      if (!k) return;
      drag.box.style.left = k.x + '%';
      drag.box.style.top = k.y + '%';
      drag.box.style.width = k.w + '%';
      drag.box.style.height = k.h + '%';
    });

    mlayer.addEventListener('pointerup', function (ev) {
      if (!drag || ev.pointerId !== drag.id) return;
      var d = drag;
      drag = null;
      /* Under 4 px either way is a click: it opens the mark under it, if any,
       * and never creates one. */
      if (Math.abs(ev.clientX - d.x) < 4 && Math.abs(ev.clientY - d.y) < 4) {
        d.box.remove();
        var r = mlayer.getBoundingClientRect();
        if (!r.width || !r.height) return;
        var px = pct(ev.clientX, r.left, r.width), py = pct(ev.clientY, r.top, r.height);
        var marks = readMarks(d.row), hit = null;
        marks.forEach(function (k, i) {
          if (k.tile === d.tile && px >= k.x && px <= k.x + k.w && py >= k.y && py <= k.y + k.h) hit = i;
        });
        if (hit !== null) {
          var m = marks[hit];
          openNote({ row: d.row, index: hit, mark: { tile: m.tile, x: m.x, y: m.y, w: m.w, h: m.h, note: m.note }, box: null });
        }
        return;
      }
      var k = rectOf(d, ev);
      /* Under 1.0 percent either way after clamping (a drag wholly off one
       * edge, or a flat line) is no region: its hit test could never match,
       * so it could never be opened or deleted. */
      if (!k || k.w < 1 || k.h < 1) { d.box.remove(); return; }
      openNote({ row: d.row, index: null, mark: k, box: d.box });
    });
    mlayer.addEventListener('pointercancel', function (ev) {
      if (!drag || ev.pointerId !== drag.id) return;
      drag.box.remove();
      drag = null;
    });

    /* Swipe: a horizontal touch drag past 40 px walks the item's images, as
     * Left/Right do. Only in the reduced mode at fit size; a gallery row keeps
     * its own, and at 1:1 a drag pans the capture (components.css). */
    var swipeFrom = null;
    body.addEventListener('pointerdown', function (ev) {
      /* Only a primary touch (no other touch held) starts one; any other
       * finger down drops it, so a pinch never walks. A press the mark layer
       * took (its handler runs first) is a mark, never a swipe (BL-649). */
      swipeFrom = ev.isPrimary && ev.pointerType === 'touch' && !drag ? { x: ev.clientX, y: ev.clientY } : null;
    });
    body.addEventListener('pointercancel', function () { swipeFrom = null; });
    body.addEventListener('pointerup', function (ev) {
      /* Only the tracked finger's lift: no other touch, mouse or pen. */
      if (!ev.isPrimary || ev.pointerType !== 'touch') return;
      var from = swipeFrom;
      swipeFrom = null;
      /* At 1:1 a drag pans — a drawing that fits the dialog has nothing to pan. */
      var pans = dlg.classList.contains('native')
        && !(dlg.classList.contains('svgmode') && !dlg.classList.contains('pan'));
      if (from === null || !dlg.classList.contains('shots') || pans) return;
      var dx = ev.clientX - from.x, dy = ev.clientY - from.y;
      if (Math.abs(dx) >= 40 && Math.abs(dx) > Math.abs(dy)) step(dx < 0 ? 1 : -1);
    });

    /* ---- every tile becomes the button ---- */
    var tiles = [];
    rows.forEach(function (row) {
      tiles = tiles.concat([].slice.call(row.querySelectorAll('figure[data-tile]')));
    });
    tiles = tiles.concat(shots);
    tiles.forEach(function (fig) {
      /* Nothing to enlarge. A gallery-row tile is img-only: Mark would stay
       * live over an empty img box for a drawing. */
      if (fig.hasAttribute('data-tile') ? !fig.querySelector('img') : !hasPicture(fig)) return;
      fig.setAttribute('role', 'button');
      fig.setAttribute('tabindex', '0');
      fig.setAttribute('title', L.zoomOpen);
      /* The visible affordance (BL-466): components.css draws this word on the
       * tile with ::after, so it is an attribute and never text in the row
       * (the question fingerprint hashes text) and a tap works as a click. */
      fig.setAttribute('data-zoom', L.zoomLabel);
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
      try {
        var v = JSON.parse(localStorage.getItem(GAL_KEY) || '{}');
        return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
      }
      catch (e) { return {}; }        /* storage refused: no filter is kept */
    }

    function galStore(id, key, value) {
      try {
        var all = galState();
        if (!all[id] || typeof all[id] !== 'object' || Array.isArray(all[id])) all[id] = {};
        all[id][key] = value;
        localStorage.setItem(GAL_KEY, JSON.stringify(all));
      } catch (e) { /* unavailable — the filter still applies in this tab */ }
    }

    var saved = galState();
    groups.forEach(function (g) {
      if (g.querySelector('.kit-galbar')) return;
      /* Mode and viewport filters mean something only on a light/dark matrix;
       * a before/after review block gets no toolbar at all. */
      if (!/(^|\s)(light|dark)-/.test(g.getAttribute('data-tiles') || '')) return;
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
          if (persist && gid) galStore(gid, f.key, value);
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
        /* A block with no id has no identity across visits: every such block
         * would share the empty key, so a filter set on one came back on the
         * others. Its filter lasts the visit. */
        var was = gid && saved[gid] && saved[gid][f.key];
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
    exclusiveNotNow();
    var recovered = restore();
    syncDefects();
    openFilledMore();
    redrawMarks();
    /* Shown when anything was DROPPED too, not only when something was
     * recovered: an answer the reader typed is missing from the page, and the
     * banner is the only thing that says why. */
    if (recovered.n || recovered.stale || recovered.spent) {
      showRestoredNote(recovered.n, recovered.stale, recovered.spent);
    }
    watchStaleTab();
    markRecommendations();
    items.forEach(updateQuiz);
    addClearControls();
    document.addEventListener('input', function () { refresh(); save(); });
    document.addEventListener('change', function (ev) {
      var q = ev.target && ev.target.closest ? ev.target.closest('.consult-item') : null;
      if (q) updateQuiz(q);
      openFilledMore(); refresh(); save();
    });
    refresh();
    buttons.forEach(function (b) { b.addEventListener('click', copy); });
  }
})();
