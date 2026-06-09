// TypeScript types for the decision-context fence grammar
// (companion to decision-context-schema.js — Task 2 of
// docs/plans/decision-context-gate-2026-05-29.md).
//
// Both the Stop hook (via `node -e require(…)`) and the GUI MUST import
// the canonical Zod-backed runtime validator from
// `decision-context-schema.js`. These types are the static-typing peer.

export type Urgency = 'low' | 'medium' | 'high' | 'critical';
export type ReversibilityCost = 'free' | 'cheap' | 'expensive' | 'irreversible';
export type AnswerShape = 'value' | 'choice' | 'yes-no' | 'opinion' | 'specific-format';
export type ActionItemState = 'open' | 'done' | 'declined' | 'stale';

export type Category =
  | 'decision'
  | 'question'
  | 'action_item_for_user'
  | 'autonomous_action';

export interface CommonEnvelope {
  id: string;
  label?: string;
  title: string;
  about: string;
  background: string;
  urgency?: Urgency;
  expires_at?: string;
  default_if_no_response?: string;
  warn_at?: string;
  blocks_on?: string[];
  connects_to?: string[];
  references?: string[];
}

export interface DecisionOption {
  key: string;
  name: string;
  what_it_does: string;
  risk: string;
  reversibility_cost: ReversibilityCost;
  cost: string;
}

export interface DecisionRecommendation {
  option_key: string;
  reasoning: string;
}

export interface DecisionPayload extends CommonEnvelope {
  category: 'decision';
  question: string;
  why_not_decide_alone: string;
  options: DecisionOption[];
  recommendation: DecisionRecommendation;
  reply_with: string;
}

export interface QuestionPayload extends CommonEnvelope {
  category: 'question';
  question: string;
  why_asking: string;
  what_ive_tried: string;
  answer_shape: AnswerShape;
}

export interface ActionItemForUserPayload extends CommonEnvelope {
  category: 'action_item_for_user';
  the_ask: string;
  why_assigned: string;
  what_im_doing_meanwhile: string;
  state: ActionItemState;
}

// autonomous_action — NO expires_at / default_if_no_response / warn_at /
// options fields. It is a fait-accompli notification of an action the agent
// already took.
export interface AutonomousActionPayload {
  category: 'autonomous_action';
  id: string;
  label?: string;
  title: string;
  about: string;
  background: string;
  urgency?: Urgency;
  blocks_on?: string[];
  connects_to?: string[];
  references: string[];        // REQUIRED, ≥1 entry
  action_taken: string;
  reasoning: string;
  reversibility: string;
}

export type FencePayload =
  | DecisionPayload
  | QuestionPayload
  | ActionItemForUserPayload
  | AutonomousActionPayload;

export interface ParsedFenceBlock {
  category: Category;
  payload: Record<string, unknown>;
}

// Throws ZodError on schema violation; returns the parsed/validated payload.
export function validateFence(
  category: 'decision', payload: unknown
): DecisionPayload;
export function validateFence(
  category: 'question', payload: unknown
): QuestionPayload;
export function validateFence(
  category: 'action_item_for_user', payload: unknown
): ActionItemForUserPayload;
export function validateFence(
  category: 'autonomous_action', payload: unknown
): AutonomousActionPayload;
export function validateFence(category: Category, payload: unknown): FencePayload;

// Safe variant: returns a Zod-style {success, data?, error?} discriminated
// union without throwing.
export function safeValidateFence(category: Category, payload: unknown): {
  success: boolean;
  data?: FencePayload;
  error?: unknown;
};

// Parse a raw Markdown fence block (`::: <category> id=… … :::`) into a
// {category, payload} pair. The payload is the RAW parsed shape — the caller
// is expected to pass it through validateFence(category, payload) for full
// semantic validation.
export function parseFenceBlock(rawText: string): ParsedFenceBlock;

export const CATEGORIES: ReadonlyArray<Category>;

// ----- self-contained item `details` content shape (Phase C, 2026-06-09) ---
// The shape the GUI detail-pane (web/app.js) renders from an item-details-set
// event's `details` payload. Both emit paths assemble it via
// assembleItemDetails so the content never diverges. `[k: string]: unknown`
// preserves forward-tolerance for passthrough metadata.
export interface ItemDetailsContent {
  _category: Category;
  background: string;
  about?: string;
  urgency?: string;
  expires_at?: string;
  warn_at?: string;
  default_if_no_response?: string;
  references?: string[];
  links?: string[];
  description?: string;
  context?: string;
  instructions?: string;
  blocking_input?: string;
  question?: string;
  why_not_decide_alone?: string;
  options?: Array<string | Record<string, unknown>>;
  recommendation?: string | { option_key?: string; reasoning?: string };
  reply_with?: string;
  why_asking?: string;
  what_ive_tried?: string;
  answer_shape?: string;
  the_ask?: string;
  why_assigned?: string;
  what_im_doing_meanwhile?: string;
  state?: string;
  action_taken?: string;
  reasoning?: string;
  reversibility?: string;
  [k: string]: unknown;
}

export const DETAIL_CATEGORIES: ReadonlyArray<Category>;

// safeParse-style validation of a details payload.
export function validateItemDetails(details: unknown): {
  success: boolean;
  data?: ItemDetailsContent;
  error?: unknown;
};

// Assemble a self-contained details object, or null when it would not be
// self-contained (no background, or no actionable field). Callers MUST treat
// null as "do not emit this item."
export function assembleItemDetails(
  category: string,
  fields: Record<string, unknown>
): ItemDetailsContent | null;

// Mirror of the decision-context-gate's `details` stamp from a validated
// fence payload; shares the same assembler.
export function fenceToDetails(
  category: Category,
  validatedFencePayload: unknown
): ItemDetailsContent | null;
