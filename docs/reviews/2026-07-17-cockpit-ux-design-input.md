# Cockpit UX redesign — operator design input (2026-07-17, verbatim intent)

Captured from the operator reviewing the LIVE cockpit (:7733). This document is the requirements
brief for the UX deep-dive; it SUPERSEDES the assumption that the current ask-tree presentation is
the right frame, and may reshape docs/plans/cockpit-ui-polish.md.

## Verbatim needs
> "The thing I'm really looking for from this is the ability to keep track of the status of
> everything that is on the roadmap: that is upcoming; that is in the works; that is partially
> done; and that is complete. I want to have a frame of reference for the status of all of that
> work and how it maps back onto the specific requests that I've made."

> "I know I said previously that each node in the tree diagram should be defined by my original
> request, but the first sentence of my prompt appears to not be a good reference for what my
> actual ask was."

> "The multitude of drift tags is not helpful." (screenshot: hundreds of identical unlabeled
> 'drift' chips — see the badge-storm nl-issue; the auditor half is a mechanism bug, the
> presentation half is a UX failure regardless)

## What this implies (analysis, to be pressure-tested in the sit-down)
1. **The operator's mental model is ROADMAP-first, not session-first.** Their four buckets —
   upcoming / in the works / partially done / complete — are WORK-ITEM lifecycle states, not
   session states. The current landing is session/ask-rooted; they are asking for an
   outcome/roadmap-rooted frame with asks/sessions as supporting evidence UNDER items.
2. **The ask-node naming is broken as designed.** Auto-capture summarizes the first ~140 chars of
   the first prompt; real asks are (a) often mid-conversation, (b) multi-part, (c) better stated
   as INTENT than as quoted prompt text. Candidate fixes to explore: LLM-distilled intent titles
   (editable), naming-at-promote (Circuit D2 promote doubles as the naming moment), merging
   multiple prompts into one work item (the "Merge into..." affordance already exists).
3. **These four buckets map cleanly onto Circuit's pipeline** (PROPOSED=upcoming; promoted+
   building=in the works; partially built=partial; merged/deployed=complete) — the redesign
   should anticipate that convergence rather than invent a parallel taxonomy.
4. Badges/telemetry must earn their place: grouped, counted, labeled, capped — or demoted off the
   primary surface entirely (anti-noise law applies to OUR OWN telemetry too).
