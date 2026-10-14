/**
 * SCCS-NY 2026 workshop — participant feedback form with a name-blind public summary.
 *
 * HOW TO USE (once):
 *   1. Create a new Google Sheet (e.g. "SCCS-NY 2026 feedback — PRIVATE").
 *   2. Extensions → Apps Script. Delete the sample code, paste this whole file, Save.
 *   3. Choose the function `setup` in the toolbar and click Run. Approve the permissions.
 *      This creates the Google Form, links it to this Sheet, and adds three tabs:
 *        Setup       – the form's links (what to paste into feedback-config.json)
 *        Moderation  – one row per response: tick "Approve comments" to publish its comments
 *        Public      – the ONLY tab to publish: counts per question + approved comments
 *   4. File → Share → Publish to web → choose the "Public" tab and "Comma-separated values (.csv)"
 *      → Publish. Copy the link into feedback-config.json as "public_csv_url".
 *
 * WHAT IS PUBLIC: question-level counts, and free-text answers only from responses you
 * approve, each list sorted alphabetically (so order says nothing about who wrote what).
 * Never public: names, emails, "main field", timestamps, response order, row-level answers.
 * The public tab rebuilds automatically on every submission and whenever you edit the
 * Moderation tab; use the "Feedback" menu → "Rebuild public summary" to force it.
 */

const TITLE = 'SCCS-NY 2026 Workshop — Participant Feedback & Questions';
const SUMMARY_URL = 'https://jjherlan.github.io/rpn-spatial/feedback-summary.html';
const LIKERT = ['1', '2', '3', '4', '5', 'N/A'];
const LEVEL3 = ['None', 'Some', 'A lot'];

// Each entry: code (stable id used by the summary page), type, title, section, and whether
// its answers may ever be published. 'private' items are never published.
const SPEC = [
  { type: 'page', title: '1. About you', help: 'Anonymous. Every question is optional.' },
  { code: 'role', type: 'checkbox', section: '1. About you', title: 'Your current role',
    choices: ['Undergraduate', 'Graduate student', 'Postdoc', 'Faculty / researcher',
              'Agency or NGO practitioner', 'Educator'], other: true },
  { code: 'field', type: 'text', private: true, section: '1. About you', title: 'Your main field (kept private)' },
  { code: 'exp_imaging', type: 'mc', section: '1. About you', title: 'Experience with underwater or reef imaging (photomosaics, SfM, 3D models)', choices: LEVEL3 },
  { code: 'exp_stats', type: 'mc', section: '1. About you', title: 'Experience with spatial statistics (point patterns, K / g functions)', choices: LEVEL3 },
  { code: 'exp_r', type: 'mc', section: '1. About you', title: 'Experience with R', choices: LEVEL3 },
  { code: 'reefs', type: 'mc', section: '1. About you', title: 'Have you worked on coral reefs or other benthic habitats?',
    choices: ['No', 'Yes, in the field', 'Yes, with data only'] },

  { type: 'page', title: '2. The workshop overall', help: '1 = strongly disagree · 3 = neutral · 5 = strongly agree' },
  { code: 'ov', type: 'grid', section: '2. The workshop overall', title: 'Rate each statement', rows: [
    'The workshop met the goals stated at the start',
    'I can explain how photos become a 3D model and a 2D map of a reef plot',
    'I can tell how many colonies (intensity) apart from how they are arranged (pattern)',
    'I can read VMR, Clark–Evans R and g(r) and say whether a pattern is clustered, random or over-dispersed',
    'I understand why different processes can produce similar patterns',
    'I see how these methods could inform reef monitoring or conservation',
    'The overall length was right',
    'The balance of looking, listening and doing was right',
    'I would recommend this workshop to a colleague'] },
  { code: 't_useful', type: 'para', section: '2. The workshop overall', title: 'What was the single most useful thing you learned?' },
  { code: 't_confusing', type: 'para', section: '2. The workshop overall', title: 'What was the least useful or most confusing part?' },

  { type: 'page', title: '3. Opening observation activity', help: 'The photos and videos from Rapa Nui, with "I notice / I wonder".' },
  { code: 'obs', type: 'grid', section: '3. Opening observation activity', title: 'Rate each statement', rows: [
    'Looking before any statistics helped me engage with the later material',
    'The images were clear and varied enough to spark questions',
    'The activity was the right length (it ran about 15–25 minutes)',
    'The talk connected back to what we noticed and wondered'] },
  { code: 't_obs_image', type: 'para', section: '3. Opening observation activity', title: 'Which image or video stuck with you, and why?' },
  { code: 't_obs_change', type: 'para', section: '3. Opening observation activity', title: 'How would you change this activity?' },

  { type: 'page', title: '4. The talk', help: 'Large-area imaging, the 3D models, the statistics and the Rapa Nui results.' },
  { code: 'talk', type: 'grid', section: '4. The talk', title: 'Rate each statement', rows: [
    'The large-area imaging steps (survey, 3D model, 2D map, colony points) were clear',
    'The 3D model fly-through videos helped me understand the reefs',
    'The "In plain language" slides made the statistics accessible',
    'The technical statistics slides were at the right level for me',
    'The four candidate processes made sense',
    'The results (DCLF tests, neighbourhood composition, "gradient of control") were convincing',
    'The slides were readable (text size, figures, colours)',
    'The pace was right'] },
  { code: 'pace', type: 'mc', section: '4. The talk', title: 'Pace overall', choices: ['Too slow', 'About right', 'Too fast'] },
  { code: 'level', type: 'mc', section: '4. The talk', title: 'Level overall', choices: ['Too basic', 'About right', 'Too advanced'] },
  { code: 't_talk_more', type: 'para', section: '4. The talk', title: 'Which slide or idea needed more explanation?' },
  { code: 't_talk_cut', type: 'para', section: '4. The talk', title: 'Was anything unnecessary or could be cut?' },

  { type: 'page', title: '5. Hands-on session: the app and worksheet' },
  { code: 'hands', type: 'grid', section: '5. Hands-on session', title: 'Rate each statement', rows: [
    'The app loaded and ran without problems on my device',
    'The app was easy to use without instructions from the front',
    'The worksheet instructions were clear',
    'Working in a small group helped',
    "The user's manual (web or PDF) was useful"] },
  { code: 'act', type: 'cbgrid', section: '5. Hands-on session', title: 'For each activity, tick how it went', rows: [
    '1 · Intensity is not pattern', '2 · Regular, random, clustered', '3 · The three real reefs',
    '4 · Pattern vs process', '5 · Neighbourhood overlap', 'Debrief'],
    cols: ['Too easy', 'About right', 'Too hard', 'Ran out of time'] },
  { code: 't_act_most', type: 'para', section: '5. Hands-on session', title: 'Which activity taught you the most? Which taught you the least?' },
  { code: 't_app_break', type: 'para', section: '5. Hands-on session', title: 'Did anything in the app break, confuse you or behave unexpectedly? (device and browser, if you remember)' },
  { code: 't_app_more', type: 'para', section: '5. Hands-on session', title: 'What would make the app more useful for your own teaching or research?' },

  { type: 'page', title: '6. Feedback for the presenter', help: 'Honest critique is welcome.' },
  { code: 'pres', type: 'grid', section: '6. Feedback for the presenter', title: 'Rate each statement', rows: [
    'The presenter explained ideas clearly, without unnecessary jargon',
    'The presenter used good examples and analogies',
    'The presenter spoke at a comfortable pace and volume',
    'The presenter checked for understanding and invited questions',
    'Questions were answered clearly and respectfully',
    'The presenter managed time well across the session',
    'I felt comfortable participating'] },
  { code: 't_keep', type: 'para', section: '6. Feedback for the presenter', title: 'One thing I should keep doing' },
  { code: 't_stop', type: 'para', section: '6. Feedback for the presenter', title: 'One thing I should stop or do differently' },
  { code: 't_start', type: 'para', section: '6. Feedback for the presenter', title: 'One thing I should start doing' },

  { type: 'page', title: '7. Recommendations for future workshops' },
  { code: 't_change', type: 'para', section: '7. Recommendations', title: 'If you could change one thing about this workshop, what would it be?' },
  { code: 't_add', type: 'para', section: '7. Recommendations', title: 'What should be added?' },
  { code: 't_cut', type: 'para', section: '7. Recommendations', title: 'What should be cut or shortened?' },
  { code: 'followup', type: 'checkbox', section: '7. Recommendations', title: 'Which follow-up would interest you?', choices: [
    'Building a 3D model from photos (Metashape / Viscore)',
    'Annotating and segmenting reef images (e.g. CoralNet, TagLab)',
    'Point-pattern analysis in R with your own data (spatstat)',
    'Field methods: planning and running a large-area imaging survey',
    'Using these methods for monitoring or restoration (e.g. outplant spacing)'], other: true },
  { code: 'format', type: 'checkbox', section: '7. Recommendations', title: 'Preferred format next time',
    choices: ['Half day', 'Full day', 'Multi-day', 'Online', 'In person', 'Hybrid'] },

  { type: 'page', title: '8. Your questions',
    help: 'Approved questions are shown, without names, on the public summary page with my replies.' },
  { code: 'q1', type: 'para', section: '8. Your questions', title: 'Question 1' },
  { code: 'q2', type: 'para', section: '8. Your questions', title: 'Question 2' },
  { code: 'q3', type: 'para', section: '8. Your questions', title: 'Question 3' },
  { code: 't_other', type: 'para', section: '8. Your questions', title: 'Any other comments' },
  { code: 'name', type: 'text', private: true, section: '8. Your questions', title: 'Optional: your name, for a personal reply (never published)' },
  { code: 'email', type: 'text', private: true, section: '8. Your questions', title: 'Optional: your email, for a personal reply (never published)' },
];

const QUESTION_CODES = ['q1', 'q2', 'q3'];
const MOD_HEADERS = ['Response ID', 'Submitted', 'Approve comments', 'Reply from presenter (public)',
                     'Free-text answers (for review)', 'Name', 'Email', 'Main field'];

function onOpen() {
  SpreadsheetApp.getUi().createMenu('Feedback')
    .addItem('Rebuild public summary', 'rebuildPublic')
    .addToUi();
}

function setup() {
  const ss = SpreadsheetApp.getActive();
  const props = PropertiesService.getScriptProperties();
  if (props.getProperty('formId')) {
    throw new Error('Setup has already run. Use the Feedback menu → Rebuild public summary.');
  }
  const form = FormApp.create(TITLE)
    .setDescription('From Photos to Spatial Pattern · SCCS-NY 2026 · American Museum of Natural History. ' +
      'About 10 minutes, anonymous, every question optional. Ratings and approved comments are summarised, ' +
      'without names, at ' + SUMMARY_URL)
    .setCollectEmail(false)
    .setProgressBar(true)
    .setShowLinkToRespondAgain(false)
    .setConfirmationMessage('Thank you! The anonymous summary is at ' + SUMMARY_URL);

  const map = {};
  SPEC.forEach(function (s, idx) {
    let item;
    if (s.type === 'page') {
      // the first section starts on page 1 (a header); later sections get their own page
      item = idx === 0 ? form.addSectionHeaderItem().setTitle(s.title) : form.addPageBreakItem().setTitle(s.title);
      if (s.help) item.setHelpText(s.help);
      return;
    }
    if (s.type === 'checkbox') item = form.addCheckboxItem().setChoiceValues(s.choices).showOtherOption(!!s.other);
    if (s.type === 'mc') item = form.addMultipleChoiceItem().setChoiceValues(s.choices);
    if (s.type === 'text') item = form.addTextItem();
    if (s.type === 'para') item = form.addParagraphTextItem();
    if (s.type === 'grid') item = form.addGridItem().setRows(s.rows).setColumns(LIKERT);
    if (s.type === 'cbgrid') item = form.addCheckboxGridItem().setRows(s.rows).setColumns(s.cols);
    item.setTitle(s.title);
    map[item.getId()] = s.code;
  });

  form.setDestination(FormApp.DestinationType.SPREADSHEET, ss.getId());   // raw backup, stays private
  props.setProperty('formId', form.getId());
  props.setProperty('itemMap', JSON.stringify(map));

  const setupSheet = sheet_(ss, 'Setup');
  setupSheet.clear();
  setupSheet.getRange(1, 1, 7, 2).setValues([
    ['Form link (share / QR code)', form.getPublishedUrl()],
    ['form_embed_url (paste into feedback-config.json)', form.getPublishedUrl() + '?embedded=true'],
    ['Form editor', form.getEditUrl()],
    ['Public summary page', SUMMARY_URL],
    ['Next step', 'File → Share → Publish to web → tab "Public" → CSV → Publish; paste that link as public_csv_url'],
    ['Never publish', 'Setup, Moderation or Form Responses tabs (they contain names, emails and raw answers)'],
    ['Moderation', 'Tick "Approve comments" on a row to publish that response\'s free-text answers (anonymously)'],
  ]);
  setupSheet.setColumnWidth(1, 330).setColumnWidth(2, 640);

  const mod = sheet_(ss, 'Moderation');
  mod.clear();
  mod.getRange(1, 1, 1, MOD_HEADERS.length).setValues([MOD_HEADERS]).setFontWeight('bold');
  mod.setFrozenRows(1);
  mod.setColumnWidth(5, 520);

  ScriptApp.newTrigger('onSubmit').forForm(form).onFormSubmit().create();
  ScriptApp.newTrigger('onModerationEdit').forSpreadsheet(ss).onEdit().create();

  rebuildPublic();
  ss.setActiveSheet(setupSheet);
  Logger.log('Form: ' + form.getPublishedUrl());
}

function onSubmit() { rebuildPublic(); }

function onModerationEdit(e) {
  if (e && e.range && e.range.getSheet().getName() === 'Moderation' && e.range.getColumn() <= 4) rebuildPublic();
}

function rebuildPublic() {
  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    const ss = SpreadsheetApp.getActive();
    const props = PropertiesService.getScriptProperties();
    const form = FormApp.openById(props.getProperty('formId'));
    const map = JSON.parse(props.getProperty('itemMap'));
    const spec = {};
    SPEC.forEach(function (s) { if (s.code) spec[s.code] = s; });

    // --- Moderation: one row per response; keep existing ticks and replies -------------
    const mod = sheet_(ss, 'Moderation');
    const last = mod.getLastRow();
    const existing = last > 1 ? mod.getRange(2, 1, last - 1, MOD_HEADERS.length).getValues() : [];
    const known = {};
    existing.forEach(function (r, i) { known[r[0]] = i; });

    const responses = form.getResponses();
    const parsed = responses.map(function (resp) {
      const a = {};
      resp.getItemResponses().forEach(function (ir) {
        const code = map[ir.getItem().getId()];
        if (code) a[code] = ir.getResponse();
      });
      return { id: resp.getId(), time: resp.getTimestamp(), a: a };
    });

    const newRows = [];
    parsed.forEach(function (p) {
      if (known[p.id] !== undefined) return;
      const texts = SPEC.filter(function (s) { return s.type === 'para' && p.a[s.code]; })
        .map(function (s) { return s.title + ': ' + p.a[s.code]; }).join('\n');
      newRows.push([p.id, p.time, false, '', texts, p.a.name || '', p.a.email || '', p.a.field || '']);
    });
    if (newRows.length) {
      const start = mod.getLastRow() + 1;
      mod.getRange(start, 1, newRows.length, MOD_HEADERS.length).setValues(newRows);
      mod.getRange(start, 3, newRows.length, 1).insertCheckboxes();
      mod.getRange(start, 5, newRows.length, 1).setWrap(true);
    }
    const modRows = mod.getLastRow() > 1 ? mod.getRange(2, 1, mod.getLastRow() - 1, 4).getValues() : [];
    const approved = {}, reply = {};
    modRows.forEach(function (r) { approved[r[0]] = r[2] === true; reply[r[0]] = String(r[3] || '').trim(); });

    // --- Aggregate (no row-level data leaves this function) ----------------------------
    const counts = {};                         // key code|row|value -> count
    const comments = [];                       // [section, code, label, text]
    const qa = [];                             // {sortKey, questions[], reply}
    function bump(code, rowLabel, value) {
      const k = code + '\u0001' + rowLabel + '\u0001' + value;
      counts[k] = (counts[k] || 0) + 1;
    }
    parsed.forEach(function (p) {
      SPEC.forEach(function (s) {
        if (!s.code || s.private) return;
        const v = p.a[s.code];
        if (v === undefined || v === null || v === '') return;
        if (s.type === 'mc') bump(s.code, s.title, v);
        if (s.type === 'checkbox') [].concat(v).forEach(function (x) {
          bump(s.code, s.title, s.choices.indexOf(x) >= 0 ? x : 'Other');
        });
        if (s.type === 'grid') v.forEach(function (x, i) { if (x) bump(s.code + '_' + (i + 1), s.rows[i], x); });
        if (s.type === 'cbgrid') v.forEach(function (xs, i) {
          (xs || []).forEach(function (x) { bump(s.code + '_' + (i + 1), s.rows[i], x); });
        });
        if (s.type === 'para' && approved[p.id] && QUESTION_CODES.indexOf(s.code) < 0) {
          comments.push([s.section, s.code, s.title, String(v).trim()]);
        }
      });
      if (approved[p.id]) {
        const qs = QUESTION_CODES.map(function (c) { return String(p.a[c] || '').trim(); }).filter(String);
        if (qs.length) qa.push({ key: hash_(p.id), qs: qs, reply: reply[p.id] });
      }
    });

    const out = [['section', 'kind', 'code', 'label', 'value', 'count', 'group']];
    out.push(['meta', 'meta', 'n_responses', 'Responses', String(parsed.length), parsed.length, '']);
    out.push(['meta', 'meta', 'updated', 'Last updated',
              Utilities.formatDate(new Date(), 'America/New_York', 'yyyy-MM-dd'), '', '']);
    SPEC.forEach(function (s) {
      if (!s.code || s.private || s.type === 'para' || s.type === 'text') return;
      const kind = s.type === 'grid' ? 'rating' : (s.type === 'cbgrid' ? 'grid' : 'choice');
      const rows = (s.type === 'grid' || s.type === 'cbgrid') ? s.rows.map(function (r, i) { return [s.code + '_' + (i + 1), r]; })
                                                              : [[s.code, s.title]];
      const values = s.type === 'grid' ? LIKERT : (s.type === 'cbgrid' ? s.cols : s.choices.concat(s.other ? ['Other'] : []));
      rows.forEach(function (rw) {
        values.forEach(function (val) {
          const n = counts[rw[0] + '\u0001' + rw[1] + '\u0001' + val] || 0;
          out.push([s.section, kind, rw[0], rw[1], val, n, s.code]);
        });
      });
    });
    const order = {};
    SPEC.forEach(function (s, i) { if (s.code) order[s.code] = i; });
    comments.sort(function (a, b) {                 // question order, then alphabetical: order reveals nothing
      return order[a[1]] !== order[b[1]] ? order[a[1]] - order[b[1]] : (a[3] < b[3] ? -1 : a[3] > b[3] ? 1 : 0);
    })
      .forEach(function (c) { out.push([c[0], 'comment', c[1], c[2], c[3], '', '']); });
    qa.sort(function (a, b) { return a.key < b.key ? -1 : 1; }).forEach(function (q, i) {
      q.qs.forEach(function (t) { out.push(['8. Your questions', 'question', 'qa', 'Question', t, '', i + 1]); });
      if (q.reply) out.push(['8. Your questions', 'reply', 'qa', 'Reply', q.reply, '', i + 1]);
    });

    const pub = sheet_(ss, 'Public');
    pub.clear();
    pub.getRange(1, 1, out.length, out[0].length).setValues(out);
  } finally {
    lock.releaseLock();
  }
}

function sheet_(ss, name) { return ss.getSheetByName(name) || ss.insertSheet(name); }

function hash_(s) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, s);
  return bytes.map(function (b) { return ('0' + (b & 0xff).toString(16)).slice(-2); }).join('');
}
