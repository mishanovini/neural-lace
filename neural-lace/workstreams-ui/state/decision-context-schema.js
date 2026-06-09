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

// ----- self-contained item `details` content shape (Phase C, 2026-06-09) --
//
// THE PROBLEM this closes (Misha, 2026-06-09): items in the Workstreams UI
// showed "INCOMPLETE METADATA" / bare fragments ("Turn 2229", a garbled
// `\" decisions…`) because the every-turn writer (workstreams-turn-emit.sh)
// stamped only a thin `details` ({kind, source, turn_index, marker}) and a
// truncated substring as `text`. The GUI's detail pane (web/app.js) renders a
// rich, self-contained card from the `item-details-set` event's `details`
// payload — `_category`, `background`, `about`, the actionable per-category
// fields, `options[]`, `recommendation`, `links[]`, `references[]`. When those
// are absent the GUI shows the "No detailed instructions recorded" fallback —
// the "INCOMPLETE METADATA" Misha saw.
//
// The directive: every emitted item must be SELF-CONTAINED for a cold reader
// who has "completely forgotten what we're doing." That means a memory-trigger
// BACKGROUND paragraph + the DECISION/QUESTION/ASK itself + OPTIONS (with
// tradeoffs) where applicable + a RECOMMENDATION + LINKS.
//
// This is the SOLE NORMATIVE content-shape for the `item-details-set`
// `details` payload. BOTH emit paths use assembleItemDetails():
//   1. decision-context-gate.sh — fence-grammar path (rich by construction).
//   2. workstreams-turn-emit.sh — deterministic every-turn path (must assemble
//      background + the actionable field, or emit NOTHING rather than garbage).
//
// schema_version is UNCHANGED (state/schema.js SCHEMA_VERSION = 1). This is a
// content-shape contract for the OPAQUE `details` payload of an existing event
// (`item-details-set`, whose required fields are node_id/item_id/details). The
// reducer treats `details` as forward-tolerant (last-writer-wins, no sub-field
// validation at the event layer — decision-context-schema.js is the SOLE
// validator for the interior). Adding/strengthening the interior content-shape
// is therefore NOT an ADR-032 §1 major bump.

const DETAIL_CATEGORIES = Object.freeze([
  'decision', 'question', 'action_item_for_user', 'autonomous_action',
]);

// The DetailOption shape the GUI renders (web/app.js options block). Lenient:
// both the fence-schema decision-option shape (key/name/what_it_does/risk/
// reversibility_cost/cost) AND the legacy {label,pros,cons} shape are accepted,
// plus a bare string. Validation here is documentary — the GUI renders
// whatever subset is present.
const DetailOptionSchema = z.union([
  z.string().min(1),
  z.object({
    key: z.string().optional(),
    name: z.string().optional(),
    label: z.string().optional(),
    what_it_does: z.string().optional(),
    risk: z.string().optional(),
    reversibility_cost: z.string().optional(),
    cost: z.string().optional(),
    pros: z.string().optional(),
    cons: z.string().optional(),
  }).passthrough(),
]);

const DetailRecommendationSchema = z.union([
  z.string().min(1),
  z.object({
    option_key: z.string().optional(),
    reasoning: z.string().optional(),
  }).passthrough(),
]);

// The self-contained `details` content shape. Required for a NON-throwaway
// item: `_category` + `background` (the memory-trigger) + at least one
// actionable field for the category. Everything else is optional but rendered
// when present. `.passthrough()` keeps forward-tolerance for any extra keys
// the GUI / future emit paths attach (surfaced_by, source, turn_index, …).
const ItemDetailsContentSchema = z.object({
  _category: z.enum(['decision', 'question', 'action_item_for_user', 'autonomous_action']),
  // The memory-trigger paragraph — load-bearing. Written for a reader who
  // forgot all context: what this is, what we were doing, why it matters.
  background: z.string().min(1),
  // about: one-paragraph framing of the surface (distinct from background).
  about: z.string().optional(),
  // shared envelope (rendered when present)
  urgency: z.string().optional(),
  expires_at: z.string().optional(),
  warn_at: z.string().optional(),
  default_if_no_response: z.string().optional(),
  references: z.array(z.string()).optional(),
  links: z.array(z.string()).optional(),
  description: z.string().optional(),
  context: z.string().optional(),
  instructions: z.string().optional(),
  blocking_input: z.string().optional(),
  // decision-specific
  question: z.string().optional(),
  why_not_decide_alone: z.string().optional(),
  options: z.array(DetailOptionSchema).optional(),
  recommendation: DetailRecommendationSchema.optional(),
  reply_with: z.string().optional(),
  // question-specific
  why_asking: z.string().optional(),
  what_ive_tried: z.string().optional(),
  answer_shape: z.string().optional(),
  // action_item_for_user-specific
  the_ask: z.string().optional(),
  why_assigned: z.string().optional(),
  what_im_doing_meanwhile: z.string().optional(),
  state: z.string().optional(),
  // autonomous_action-specific
  action_taken: z.string().optional(),
  reasoning: z.string().optional(),
  reversibility: z.string().optional(),
}).passthrough().superRefine(function (val, ctx) {
  // At least one actionable field for the category — otherwise the card has a
  // background but nothing to act on (still "incomplete" for the operator).
  var cat = val._category;
  function need(fields, label) {
    var has = fields.some(function (f) {
      return val[f] != null && String(val[f]).trim() !== '';
    });
    if (!has) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: [label],
        message: cat + ' details require at least one of: ' + fields.join(', '),
      });
    }
  }
  if (cat === 'decision') need(['question', 'options', 'the_ask', 'description'], 'actionable');
  else if (cat === 'question') need(['question', 'why_asking', 'description'], 'actionable');
  else if (cat === 'action_item_for_user') need(['the_ask', 'instructions', 'description'], 'actionable');
  else if (cat === 'autonomous_action') need(['action_taken', 'reasoning', 'description'], 'actionable');
});

// validateItemDetails(details) → {success, data?, error?}. The normative check
// the every-turn writer runs BEFORE emitting an item-details-set: if it fails
// (no background, no actionable field), the writer emits NOTHING rather than a
// half-filled "INCOMPLETE METADATA" card.
function validateItemDetails(details) {
  return ItemDetailsContentSchema.safeParse(details);
}

// assembleItemDetails(category, fields) → a self-contained details object, OR
// null when the result would not be self-contained (no background, or no
// actionable field). Callers MUST treat a null return as "do not emit this
// item." This is the single normative assembler both emit paths use so the
// content shape never diverges between the fence path and the turn path.
//
// fields: any subset of the ItemDetailsContentSchema keys (background, about,
// question, options, recommendation, the_ask, instructions, links, …) PLUS
// arbitrary passthrough metadata (surfaced_by, source, …). category is
// authoritative and overrides any _category in fields.
function assembleItemDetails(category, fields) {
  if (DETAIL_CATEGORIES.indexOf(category) === -1) return null;
  var draft = Object.assign({}, fields || {}, { _category: category });
  var v = validateItemDetails(draft);
  if (!v.success) return null;
  return v.data;
}

// fenceToDetails(category, validatedFencePayload) → the details object the
// decision-context-gate stamps. Mirrors that gate's existing
// `Object.assign({}, data, { _category, surfaced_by })` exactly so the two
// paths share ONE assembler. The fence payload already carries background +
// the per-category actionable fields (the Zod fence schemas REQUIRE them), so
// this returns a populated object; null only if a malformed payload slipped
// through (defensive).
function fenceToDetails(category, validatedFencePayload) {
  var f = Object.assign({}, validatedFencePayload || {}, {
    surfaced_by: 'decision-context-gate',
  });
  delete f.category; // fence payload uses `category`; details uses `_category`
  return assembleItemDetails(category, f);
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
  // Self-contained item `details` content shape (Phase C, 2026-06-09)
  DETAIL_CATEGORIES: DETAIL_CATEGORIES,
  ItemDetailsContentSchema: ItemDetailsContentSchema,
  validateItemDetails: validateItemDetails,
  assembleItemDetails: assembleItemDetails,
  fenceToDetails: fenceToDetails,
};

// ----- self-test (node decision-context-schema.js --self-test) -------------
// Exercises the Phase-C content-shape assembler + the existing fence validator
// so the schema module has its OWN green check (the gate + GUI also exercise
// it, but a module-local self-test is the harness's native verification idiom).
if (require.main === module && process.argv[2] === '--self-test') {
  var pass = 0, fail = 0;
  function ck(name, cond) {
    if (cond) { console.log('PASS: ' + name); pass++; }
    else { console.log('FAIL: ' + name); fail++; }
  }

  // SC1: a fully-populated decision details object validates.
  var d1 = assembleItemDetails('decision', {
    background: 'We are deciding whether to apply migration m162 to prod. '
      + 'It drops a legacy column irreversibly and gates the R23 launch.',
    question: 'Apply m162 to production now, or wait for a backup window?',
    options: [
      { key: 'now', name: 'Apply now', what_it_does: 'drops the column', risk: 'no rollback', reversibility_cost: 'irreversible', cost: '5 min' },
      { key: 'wait', name: 'Wait for backup', what_it_does: 'snapshot first', risk: 'delays launch', reversibility_cost: 'cheap', cost: '1 hr' },
    ],
    recommendation: { option_key: 'wait', reasoning: 'irreversible drop warrants a backup' },
    links: ['docs/plans/r23.md'],
  });
  ck('SC1 decision assembles (background+question+options)', d1 !== null);
  ck('SC1 _category stamped', d1 && d1._category === 'decision');
  ck('SC1 background present', d1 && /m162/.test(d1.background));
  ck('SC1 options carried', d1 && Array.isArray(d1.options) && d1.options.length === 2);

  // SC2: a question with background + question.
  var d2 = assembleItemDetails('question', {
    background: 'Choosing the Twilio number for the demo-org campaign.',
    question: 'Which Twilio number should the campaign use?',
    why_asking: 'Locks the demo-org messaging identity before launch.',
  });
  ck('SC2 question assembles', d2 !== null && d2._category === 'question');

  // SC3: MISSING background → null (the "INCOMPLETE METADATA" guard).
  var d3 = assembleItemDetails('decision', {
    question: 'Apply m162 now?',
    options: [{ name: 'a' }, { name: 'b' }],
  });
  ck('SC3 no background → null (incomplete-metadata guard)', d3 === null);

  // SC4: background present but NO actionable field → null.
  var d4 = assembleItemDetails('decision', {
    background: 'Some context about a thing that happened a while ago.',
  });
  ck('SC4 background but no actionable field → null', d4 === null);

  // SC5: action_item_for_user with the_ask + background.
  var d5 = assembleItemDetails('action_item_for_user', {
    background: 'TWLO-006 launch-blocker: the demo org has no twilio_config row, '
      + 'so outbound SMS will 500 on launch day.',
    the_ask: 'Wire the demo org twilio_config (account SID + auth token).',
    why_assigned: 'Requires the live Twilio credentials only you hold.',
    what_im_doing_meanwhile: 'Drafting the config migration scaffold.',
  });
  ck('SC5 action_item assembles', d5 !== null && d5._category === 'action_item_for_user');

  // SC6: unknown category → null.
  ck('SC6 unknown category → null', assembleItemDetails('bogus', { background: 'x', question: 'y' }) === null);

  // SC7: fenceToDetails round-trips a validated fence payload (decision).
  var fence = validateFence('decision', {
    id: 'sc7', title: 'sc7 decision', about: 'about text here',
    background: 'background memory-trigger paragraph for sc7',
    question: 'pick A or B?', why_not_decide_alone: 'it changes the API contract',
    options: [
      { key: 'a', name: 'A', what_it_does: 'does A', risk: 'low', reversibility_cost: 'cheap', cost: '1h' },
      { key: 'b', name: 'B', what_it_does: 'does B', risk: 'mid', reversibility_cost: 'cheap', cost: '2h' },
    ],
    recommendation: { option_key: 'a', reasoning: 'simpler' },
    reply_with: '"take A"',
  });
  var fd = fenceToDetails('decision', fence);
  ck('SC7 fenceToDetails carries background', fd !== null && /sc7/.test(fd.background));
  ck('SC7 fenceToDetails stamps _category not category', fd && fd._category === 'decision' && fd.category === undefined);
  ck('SC7 fenceToDetails surfaced_by stamped', fd && fd.surfaced_by === 'decision-context-gate');

  console.log('\nself-test: ' + pass + ' pass, ' + fail + ' fail');
  if (fail === 0) { console.log('self-test: OK ' + pass + '/' + (pass + fail)); process.exit(0); }
  else { console.log('self-test: FAIL'); process.exit(1); }
}
