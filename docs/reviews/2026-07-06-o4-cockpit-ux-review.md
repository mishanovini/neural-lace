# O.4 cockpit rebuild — plan-time UX review (pre-dispatch gate)

Reviewer: ux-designer agent (heuristic evaluation + cognitive walkthrough), 2026-07-06.
Subject: specs-o §O.4 (docs/plans/nl-observability-program-2026-08-specs-o.md) vs the
normative sketch (docs/reviews/2026-07-04-observability-design-sketch.md) and the
current shell (workstreams-ui/). Audience: sole operator, harness maintainer;
**distrust-recovery is a binding design constraint** (v1 failed completely).

**Verdict: FAIL (build-blocking) until the amendments below are folded into the O.4
builder prompt.** Six-pane concept sound; every gap is an unspecified state or an
undispositioned legacy surface. All findings are plan amendments, foldable verbatim.

## Binding amendments (Critical, severity 3–4)

1. **error-masked-as-empty (S4).** Per-subcommand cache entries carry
   `{data, rc, stderr_tail, derived_at}`; rc≠0 renders a named ERROR state (plain
   language + stderr tail + Retry wired to the refresh endpoint + the failing `nl`
   command line) — NEVER the empty state. All six panes + the why-drawer get explicit
   empty/loading/error/ideal copy. Q1's empty state self-certifies against the
   heartbeat-pipeline health verdict ("No live sessions (oracle: heartbeats dir, 0
   files; heartbeat pipeline: <verdict>)"). Global invariant stated once.
2. **write-path-to-retired-sink (S4).** Enumerate every GUI write feature (+ capture,
   my-tasks CRUD, backlog promote, decision approve/decline/respond, branch retitle,
   POST /api/event) and per feature RETIRE the affordance or re-point to a living
   sink. Rule: no interactive element ships unless its data sink appears in
   observability-consumer-map.json or a named durable file.
3. **implicit-state-reset (S3).** Q3 last-look advances ONLY on an explicit "Mark
   seen" button with feedback; first-use window 24h; the anchor timestamp always
   renders (incl. in the empty state: "Nothing shipped since your last look, 2h
   ago"). Every client-persisted key gets write-trigger + read-effect + reset-path.
4. **unlabeled-data-age (S3).** /api/health + freshness badge re-specced onto
   derived-cache stamps (current sources are retired by deliverable 4 — an unamended
   badge would show false-stale forever). Header: "derived <age> ago", stale accent
   when age > 2× refresh interval OR last refresh failed, + Refresh-now with
   in-flight/succeeded/failed feedback. Every trust-bearing datum names its own age
   (doctor verdict "as of <ts>", Q5 window, Q3 anchor, Q1 derivation time). Keep the
   ui_build auto-reload.
5. **duplicate-count-different-oracle (S3).** Q2's open-entry count (oracle:
   needs-you ledger) is THE canonical needs-me number. Q1's WAITING-ON-ME is a
   per-session FLAG (never summed/displayed as a count) cross-linking to that
   session's Q2 entries; Q2 entries with absent/concluded sessions render a
   "session gone" marker. CANONICAL-COUNTERS-01 applies to the UI: every rendered
   number IS an oracle output (label carried through) or a per-row flag.
6. **local-path-rendered-as-hyperlink (S3).** ONE link-resolver component used by
   Q2/Q3/Q6: http(s) → `<a target=_blank>`; local/repo path → existing /api/doc
   viewer + open-in-editor; unresolvable → plain text + copy affordance; SHAs get
   copy-to-clipboard. No pane grows its own link handling.

## Binding amendments (Important, severity 2)

7. **derived-taxonomy-mismatch.** Reconcile `crashed` into the chip taxonomy: C1
   defines crashed (stale + dead pid); C4/O.4 enums must match. Chips carry tooltips
   stating their mechanical derivation rule; unobserved-cloud styled as UNKNOWN
   (muted), never ok/error.
8. **ambiguous-affordance.** Interaction table required: session row → detail incl.
   Why drawer; WAITING-ON-ME chip → its Q2 entries; Q4 waiver-dominant gate → its 7d
   numbers; drift badge → mismatch detail; everything else explicitly static, styled
   non-interactive.
9. **attention-semantics.** Q2 on top; Q1 second with stalled/crashed sorted first;
   Q4/Q5 compact strips; Q6 on-demand. Port the shell's C6 rule: ONE accent color,
   spent only on interrupt-worthy classes (needs-me>0, stalled/crashed, doctor
   RED/drift). Everything else neutral.
10. **alarm-without-diagnosis.** Drift badge quiet state = "reconciler: 0 drift
    (checked <ts>)"; firing = "drift: N claims" expanding to per-mismatch list
    (tree says X, derived says Y, "derived is authoritative") + ledger event id.
    Same discipline for doctor RED / waiver-dominant surfaces.
11. **why-drawer dead end.** Empty state: "No ledger events for <sid> (oracle:
    signal ledger). Likely: cloud/unobserved session, or started before
    turn-tracing" + equivalent `nl why` command line; error state per #1; Esc/close
    + focus-return per shell modal conventions.
12. **a11y baseline (WCAG 2.2 AA).** Chips = text + color (never color-only); real
    buttons/anchors, keyboard-operable, visible focus ≥3:1; drawer role=dialog,
    focus managed, Esc closes; aria-live=polite refresh regions; targets ≥24px;
    text ≥4.5:1. Acceptance drill includes one keyboard-only pass.
13. (Polish) Panes stack single-column below ~800px, Q2 first.

## Orchestrator dispositions on the reviewer's three questions (decide-and-go, §8)

- **Q2 actionability → READ-ONLY for O.4 v1.** No action buttons on Q2; answers
  happen in sessions/chat; the plan SAYS so explicitly so the builder does not
  half-port the old approve/decline modal. A Resolve action (shelling
  `needs-you.sh resolve`) is a legitimate future increment (its sink is the
  canonical ledger, not the retired tree) — deferred to post-O.7 drill evidence.
  Reversible.
- **Legacy write features → RETIRE entirely** (+ capture, my-tasks, promote,
  approve/decline, POST /api/event). The thin-view law wins; the capture habit is
  served by nl-issue.sh and the backlog loop. Reversible (one revert restores).
- **Docs browser → KEEP.** It becomes the link-resolver backend (finding 6).

These dispositions + all 13 amendments fold verbatim into the O.4 builder prompt at
batch-3 dispatch. The end-user-advocate's plan-time acceptance scenarios (running in
parallel) must cover: keyboard-only pass, error-state honesty, drift badge, and the
canonical needs-me count equality vs `nl needs-me --json`.
