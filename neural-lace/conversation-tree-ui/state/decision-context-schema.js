'use strict';
// SOLE NORMATIVE parser + validator for the decision-context fence grammar
// (Task 2 of docs/plans/decision-context-gate-2026-05-29.md).
//
// Both the Stop hook (via `node -e require("./decision-context-schema.js")…`)
// AND the GUI MUST import THIS module. NO shell re-implementation. NO parallel
// parser anywhere. The fence grammar is:
//
//   ::: <category> id=<id> [urgency=<value>] [reversibility_cost=<value>]
//   **About:** ...
//   **Background:** ...
//   **<category-specific bold-prefixed fields>**
//   :::
//
// Four categories share a common envelope:
//   id, label, title, about, background, urgency, expires_at,
//   default_if_no_response, warn_at, blocks_on, connects_to, references
// Plus category-specific fields per the plan's Section B grammar.
//
// Cross-field constraint (REQUIRED at the Zod layer): for `decision`,
// `question`, `action_item_for_user` — if `expires_at` is set, then
// `default_if_no_response` MUST be set AND must reference an option whose
// `reversibility_cost` is `free` or `cheap`. `autonomous_action` is exempt
// (it has no expires_at / default_if_no_response / options fields).

const { z } = require('zod');

// ----- enums --------------------------------------------------------------
const Urgency = z.enum(['low', 'medium', 'high', 'critical']).optional();
const ReversibilityCost = z.enum(['free', 'cheap', 'expensive', 'irreversible']);
const AnswerShape = z.enum(['value', 'choice', 'yes-no', 'opinion', 'specific-format']);
const ActionItemState = z.enum(['open', 'done', 'declined', 'stale']);

// ----- common envelope (all four categories) ------------------------------
// Required: id, title, about, background.
// Optional: label, urgency, expires_at, default_if_no_response, warn_at,
//   blocks_on, connects_to, references.
const CommonEnvelopeShape = {
  id: z.string().min(1),
  label: z.string().optional(),
  title: z.string().min(1),
  about: z.string().min(1),
  background: z.string().min(1),
  urgency: Urgency,
  expires_at: z.string().optional(),                  // ISO-8601 — string form (lenient)
  default_if_no_response: z.string().optional(),      // option-key reference (for decision) or free text
  warn_at: z.string().optional(),
  blocks_on: z.array(z.string()).optional(),
  connects_to: z.array(z.string()).optional(),
  references: z.array(z.string()).optional(),
};

// ----- per-category schemas ----------------------------------------------

// `decision`: one of N options with explicit reversibility_cost on each.
const OptionSchema = z.object({
  key: z.string().min(1),
  name: z.string().min(1),
  what_it_does: z.string().min(1),
  risk: z.string().min(1),
  reversibility_cost: ReversibilityCost,
  cost: z.string().min(1),
});

const RecommendationSchema = z.object({
  option_key: z.string().min(1),
  reasoning: z.string().min(1),
});

const DecisionSchema = z.object({
  ...CommonEnvelopeShape,
  category: z.literal('decision'),
  question: z.string().min(1),
  why_not_decide_alone: z.string().min(1),
  options: z.array(OptionSchema).min(2),
  recommendation: RecommendationSchema,
  reply_with: z.string().min(1),
}).superRefine(function (val, ctx) {
  // Cross-field: expires_at set ⇒ default_if_no_response set ⇒ references
  // an option whose reversibility_cost is free or cheap.
  if (val.expires_at != null && val.expires_at !== '') {
    if (val.default_if_no_response == null || val.default_if_no_response === '') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['default_if_no_response'],
        message: 'expires_at set requires default_if_no_response',
      });
      return;
    }
    const ref = val.default_if_no_response;
    const opt = val.options.find(function (o) { return o.key === ref; });
    if (!opt) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['default_if_no_response'],
        message: 'default_if_no_response "' + ref + '" must reference an option.key',
      });
      return;
    }
    if (opt.reversibility_cost !== 'free' && opt.reversibility_cost !== 'cheap') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['default_if_no_response'],
        message: 'default_if_no_response option must have reversibility_cost free|cheap (got '
          + opt.reversibility_cost + ')',
      });
    }
  }
});

// `question`: a request for a value/choice/opinion the user must supply.
const QuestionSchema = z.object({
  ...CommonEnvelopeShape,
  category: z.literal('question'),
  question: z.string().min(1),
  why_asking: z.string().min(1),
  what_ive_tried: z.string().min(1),
  answer_shape: AnswerShape,
}).superRefine(function (val, ctx) {
  if (val.expires_at != null && val.expires_at !== '') {
    if (val.default_if_no_response == null || val.default_if_no_response === '') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['default_if_no_response'],
        message: 'expires_at set requires default_if_no_response',
      });
    }
    // Note: question has no options[]; default_if_no_response is free text but
    // by convention is a cheap/free path (the agent's fallback). We cannot
    // verify reversibility_cost without options — the discipline lives in the
    // agent's authoring (and end-user-advocate review).
  }
});

// `action_item_for_user`: assigned task with current state.
const ActionItemForUserSchema = z.object({
  ...CommonEnvelopeShape,
  category: z.literal('action_item_for_user'),
  the_ask: z.string().min(1),
  why_assigned: z.string().min(1),
  what_im_doing_meanwhile: z.string().min(1),
  state: ActionItemState,
}).superRefine(function (val, ctx) {
  if (val.expires_at != null && val.expires_at !== '') {
    if (val.default_if_no_response == null || val.default_if_no_response === '') {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ['default_if_no_response'],
        message: 'expires_at set requires default_if_no_response',
      });
    }
  }
});

// `autonomous_action`: log of an action the agent took unilaterally. NO
// expires_at / default_if_no_response / options fields — it's a fait
// accompli notification, not a pending decision.
const AutonomousActionSchema = z.object({
  // Common envelope subset: id, label, title, about, background, urgency,
  // blocks_on, connects_to, references — but NOT expires_at /
  // default_if_no_response / warn_at (no pending deadline).
  id: z.string().min(1),
  label: z.string().optional(),
  title: z.string().min(1),
  about: z.string().min(1),
  background: z.string().min(1),
  urgency: Urgency,
  blocks_on: z.array(z.string()).optional(),
  connects_to: z.array(z.string()).optional(),
  references: z.array(z.string()).optional(),
  category: z.literal('autonomous_action'),
  action_taken: z.string().min(1),
  reasoning: z.string().min(1),
  reversibility: z.string().min(1),
  // autonomous_action also REQUIRES at least one reference (per plan: emits
  // the autonomous-action-logged ADR-032 §2 event w/ references[]).
}).refine(function (val) {
  return Array.isArray(val.references) && val.references.length >= 1;
}, { path: ['references'], message: 'autonomous_action requires at least one reference' });

// ----- category dispatch --------------------------------------------------
const CATEGORIES = Object.freeze([
  'decision', 'question', 'action_item_for_user', 'autonomous_action',
]);

const SCHEMA_BY_CATEGORY = Object.freeze({
  'decision': DecisionSchema,
  'question': QuestionSchema,
  'action_item_for_user': ActionItemForUserSchema,
  'autonomous_action': AutonomousActionSchema,
});

// validateFence(category, payload) → returns parsed payload on success;
// throws ZodError on failure. Callable from a shell `node -e` line as:
//   node -e 'const {validateFence}=require("./decision-context-schema.js");
//            validateFence("decision", JSON.parse(process.argv[1]));' "$PAYLOAD"
function validateFence(category, payload) {
  if (CATEGORIES.indexOf(category) === -1) {
    throw new Error('unknown category: ' + String(category)
      + ' (expected one of ' + CATEGORIES.join('|') + ')');
  }
  const schema = SCHEMA_BY_CATEGORY[category];
  // Inject category for the discriminator; allow caller to omit it (the
  // category arg is authoritative).
  const withCat = Object.assign({}, payload, { category: category });
  return schema.parse(withCat);
}

// safeValidateFence(category, payload) → returns {success, data?, error?}.
// Same contract as Zod's .safeParse but routed through the dispatcher.
function safeValidateFence(category, payload) {
  if (CATEGORIES.indexOf(category) === -1) {
    return { success: false, error: new Error('unknown category: ' + String(category)) };
  }
  const schema = SCHEMA_BY_CATEGORY[category];
  const withCat = Object.assign({}, payload, { category: category });
  return schema.safeParse(withCat);
}

// ----- fence-block parser (Markdown ::: <category> id=… … :::) ------------
//
// Grammar:
//   Line 1: `::: <category> id=<id> [key=value]*`
//   Body:   Markdown lines. Bold-prefixed fields (`**Field name:**`) become
//           keys; their value is the rest of the line (and any indented
//           continuation lines until the next `**Field:**` or end of fence).
//   List fields (options[], blocks_on, references, connects_to) are parsed
//   as YAML-ish nested blocks. For OPTIONS we expect a numbered or bulleted
//   list where each item is `**<name>** (key=<key>)` and sub-fields are
//   indented bold-prefixed lines. For blocks_on / references / connects_to
//   we accept either inline comma-separated values or one-per-line.
//   Last line: a line containing only `:::`.
//
// parseFenceBlock(rawText) → { category, payload }. Throws on malformed
// fence shell (missing opener, missing closer, unknown category). The
// returned payload is the RAW parsed object — the caller is expected to
// pass it through validateFence(category, payload) for full semantic
// validation.

const FIELD_NAME_TO_KEY = Object.freeze({
  'label': 'label',
  'title': 'title',
  'about': 'about',
  'background': 'background',
  'urgency': 'urgency',
  'expires at': 'expires_at',
  'expires_at': 'expires_at',
  'default if no response': 'default_if_no_response',
  'default_if_no_response': 'default_if_no_response',
  'warn at': 'warn_at',
  'warn_at': 'warn_at',
  'blocks on': 'blocks_on',
  'blocks_on': 'blocks_on',
  'connects to': 'connects_to',
  'connects_to': 'connects_to',
  'references': 'references',
  // decision-specific
  'question': 'question',
  'why not decide alone': 'why_not_decide_alone',
  'why_not_decide_alone': 'why_not_decide_alone',
  'options': 'options',
  'recommendation': 'recommendation',
  'reply with': 'reply_with',
  'reply_with': 'reply_with',
  // question-specific
  'why asking': 'why_asking',
  'why_asking': 'why_asking',
  "what i've tried": 'what_ive_tried',
  'what ive tried': 'what_ive_tried',
  'what_ive_tried': 'what_ive_tried',
  'answer shape': 'answer_shape',
  'answer_shape': 'answer_shape',
  // action_item_for_user-specific
  'the ask': 'the_ask',
  'the_ask': 'the_ask',
  'why assigned': 'why_assigned',
  'why_assigned': 'why_assigned',
  "what i'm doing meanwhile": 'what_im_doing_meanwhile',
  'what im doing meanwhile': 'what_im_doing_meanwhile',
  'what_im_doing_meanwhile': 'what_im_doing_meanwhile',
  'state': 'state',
  // autonomous_action-specific
  'action taken': 'action_taken',
  'action_taken': 'action_taken',
  'reasoning': 'reasoning',
  'reversibility': 'reversibility',
});

const LIST_FIELDS = Object.freeze(new Set([
  'blocks_on', 'connects_to', 'references',
]));

function _parseOpenerLine(line) {
  // `::: <category> id=<id> [urgency=<val>] [reversibility_cost=<val>]`
  // Tolerate trailing whitespace and additional key=val pairs (forward-compat).
  const m = line.match(/^:::\s+(\S+)\s+(.*)$/);
  if (!m) throw new Error('malformed fence opener: ' + line);
  const category = m[1];
  const rest = m[2];
  // Parse key=value pairs separated by whitespace.
  const out = {};
  const re = /(\w+)=("[^"]*"|\S+)/g;
  let mm;
  while ((mm = re.exec(rest)) !== null) {
    let v = mm[2];
    if (v[0] === '"' && v[v.length - 1] === '"') v = v.slice(1, -1);
    out[mm[1]] = v;
  }
  if (!out.id) throw new Error('fence opener missing id=…: ' + line);
  return { category: category, attrs: out };
}

function _parseListInline(s) {
  // Inline comma-separated list, or `["a","b"]`-style array. Tolerate both.
  const t = s.trim();
  if (t === '') return [];
  if (t[0] === '[') { try { return JSON.parse(t); } catch (_) { /* fall through */ } }
  return t.split(',').map(function (x) { return x.trim(); }).filter(function (x) { return x.length > 0; });
}

function _parseOptionsBlock(lines) {
  // Each option is a sub-block introduced by `- **<name>** (key=<key>)` or
  // `1. **<name>** (key=<key>)`. Sub-fields are indented `  **What it does:** …`
  // lines under the option. We accept the simpler form too: each option as a
  // JSON-ish indented block.
  const opts = [];
  let cur = null;
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    const header = ln.match(/^\s*(?:[-*]|\d+\.)\s+\*\*([^*]+)\*\*\s*(?:\(key=([^)]+)\))?\s*$/);
    if (header) {
      if (cur) opts.push(cur);
      cur = { key: (header[2] || '').trim(), name: header[1].trim() };
      continue;
    }
    if (!cur) continue;
    const sub = ln.match(/^\s+\*\*([^*]+):\*\*\s*(.*)$/);
    if (sub) {
      const k = sub[1].trim().toLowerCase().replace(/\s+/g, '_');
      cur[k] = sub[2].trim();
    }
  }
  if (cur) opts.push(cur);
  return opts;
}

function _parseRecommendationBlock(lines) {
  // Two sub-fields: `**Option key:**` (or `**Choose:**`) and `**Reasoning:**`.
  const out = {};
  for (let i = 0; i < lines.length; i++) {
    const ln = lines[i];
    const m = ln.match(/^\s*\*\*([^*]+):\*\*\s*(.*)$/);
    if (!m) continue;
    const k = m[1].trim().toLowerCase().replace(/\s+/g, '_');
    if (k === 'option_key' || k === 'choose' || k === 'key') out.option_key = m[2].trim();
    else if (k === 'reasoning' || k === 'why') out.reasoning = m[2].trim();
  }
  return out;
}

function parseFenceBlock(rawText) {
  if (typeof rawText !== 'string') throw new Error('parseFenceBlock requires a string');
  const allLines = rawText.split(/\r?\n/);
  // Find opener (first line beginning with `::: ` followed by a category token).
  let i = 0;
  while (i < allLines.length && !/^:::\s+\S/.test(allLines[i])) i++;
  if (i >= allLines.length) throw new Error('no fence opener (::: <category> id=…) found');
  const opener = _parseOpenerLine(allLines[i]);
  // Find matching closer (line containing only `:::` after the opener).
  let j = i + 1;
  while (j < allLines.length && allLines[j].trim() !== ':::') j++;
  if (j >= allLines.length) throw new Error('no fence closer (line containing only ":::") found');
  const bodyLines = allLines.slice(i + 1, j);

  if (CATEGORIES.indexOf(opener.category) === -1) {
    throw new Error('unknown category in fence opener: ' + opener.category);
  }

  // Walk body. Bold-prefixed `**Field:**` starts a new field; continuation
  // lines (indented OR plain text not starting with `**Header:**`) accumulate.
  const payload = { id: opener.attrs.id };
  if (opener.attrs.urgency) payload.urgency = opener.attrs.urgency;
  // reversibility_cost on the opener line is informational only — the actual
  // per-option reversibility_cost is set inside each option's sub-block.

  let curKey = null;
  let curBuf = [];
  let curSubBlockLines = null; // for options / recommendation: collect raw sub-lines

  function flush() {
    if (curKey == null) return;
    if (curKey === 'options') {
      payload.options = _parseOptionsBlock(curSubBlockLines || []);
    } else if (curKey === 'recommendation') {
      payload.recommendation = _parseRecommendationBlock(curSubBlockLines || []);
    } else {
      const joined = curBuf.join('\n').trim();
      if (LIST_FIELDS.has(curKey)) {
        payload[curKey] = _parseListInline(joined);
      } else {
        payload[curKey] = joined;
      }
    }
    curKey = null;
    curBuf = [];
    curSubBlockLines = null;
  }

  for (let k = 0; k < bodyLines.length; k++) {
    const ln = bodyLines[k];
    const hdr = ln.match(/^\*\*([^*]+):\*\*\s*(.*)$/);
    if (hdr) {
      flush();
      const rawName = hdr[1].trim().toLowerCase();
      const key = FIELD_NAME_TO_KEY[rawName] || rawName.replace(/\s+/g, '_');
      curKey = key;
      const inlineVal = hdr[2];
      if (key === 'options' || key === 'recommendation') {
        curSubBlockLines = [];
        // Inline value (rare) for these is ignored — they're block-shaped.
      } else {
        curBuf = inlineVal ? [inlineVal] : [];
      }
      continue;
    }
    if (curKey === 'options' || curKey === 'recommendation') {
      if (curSubBlockLines !== null) curSubBlockLines.push(ln);
      continue;
    }
    // Continuation line for the current field (skip blank).
    if (curKey != null && ln.trim() !== '') curBuf.push(ln);
  }
  flush();

  return { category: opener.category, payload: payload };
}

// ----- exports ------------------------------------------------------------
module.exports = {
  // Enums
  Urgency: Urgency,
  ReversibilityCost: ReversibilityCost,
  AnswerShape: AnswerShape,
  ActionItemState: ActionItemState,
  // Per-category Zod schemas
  DecisionSchema: DecisionSchema,
  QuestionSchema: QuestionSchema,
  ActionItemForUserSchema: ActionItemForUserSchema,
  AutonomousActionSchema: AutonomousActionSchema,
  // Inventory + dispatchers
  CATEGORIES: CATEGORIES,
  SCHEMA_BY_CATEGORY: SCHEMA_BY_CATEGORY,
  validateFence: validateFence,
  safeValidateFence: safeValidateFence,
  // Fence-block parser (text → {category, payload})
  parseFenceBlock: parseFenceBlock,
};
