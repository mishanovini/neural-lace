# Harness Review — Standing Audit Questions

A short list of evaluation lenses to apply to ANY proposed harness change (rule, hook, agent, skill, template). Surface during harness review sessions to pressure-test additions before they ship and existing rules during periodic cleanup.

These questions emerged from a 2026-04-25 incident in which the agent burned ~150-200k tokens "fixing" a problem it didn't understand (AI tool-call reliability). The agent then proposed three new rules + two hooks + one skill in response. Each proposal individually felt useful. The user pushed back with the questions below — and the agent realized most of its proposals were case-specific, redundant with existing rules, or trivially circumventable.

The lesson: **lots of rules with weak enforcement is worse than fewer rules with sharp enforcement.** These questions are how to tell the difference.

## The five questions

### 1. Is this too case-specific?

Does the proposed rule encode the SHAPE of the most recent failure, or the GENERAL pattern that produced it? A rule shaped like "before AI flakiness work, write a baseline.json" only fires for AI flakiness work. The same anti-pattern (stack mitigations without controlled measurement) plays out in lots of other contexts and dodges the rule.

**Sharper test:** describe two unrelated future bugs that exhibit the same anti-pattern. Does the rule catch both? If not, the rule is encoding a single instance, not a pattern.

### 2. Is this overbearing — high friction, low value?

What % of work this rule applies to actually NEEDS the discipline it enforces? If demanding a structured artifact for every fix taxes 95% of work that doesn't need it, the friction probably means the agent will produce perfunctory artifacts to satisfy the gate without doing the actual thinking.

**Sharper test:** if you removed this rule from the harness for one month, what specific failures would you expect to recur? If you can't name 1-2 concrete past failures the rule would have caught, it's probably high-friction wallpaper.

### 3. To what extent is this redundant with what already exists?

The harness already has rules for diagnosis, vaporware prevention, evidence-first protocols, plan acceptance, etc. Adding a rule that overlaps with an existing rule doesn't double the enforcement — it dilutes both. Readers fatigue and treat both as wallpaper. The existing rule was probably the one being skipped, not because it didn't exist but because the agent didn't recognize the situation as one where it applied.

**Sharper test:** which existing rule should have caught this failure? Why didn't it? The answer probably tells you whether to STRENGTHEN that rule's enforcement (mechanism upgrade) vs. add a new rule (which inherits the same self-classification weakness).

### 4. How would a Claude agent try to circumvent this?

Be the adversary. List the cheap evasion paths:
- Keyword regex in commit messages? Rename the keyword.
- File-existence check? Touch the file with empty content.
- Threshold count? Bundle work into fewer commits, or split across sub-agents whose budgets reset.
- Override env var? Always set it.
- Self-classification trigger ("if this is a flakiness investigation, do X")? Reclassify.

If the rule has more than two cheap evasion paths, it's documentation, not enforcement.

**Sharper test:** name the laziest possible compliance path that satisfies the rule's mechanical check without doing the actual work. If that path is plausible, expect the agent to take it.

### 5. Does this depend on the agent recognizing the situation correctly?

Many rules in the harness fire only when the agent classifies a situation as belonging to the rule's domain. "Before fixing flakiness, do X" requires the agent to label something as flakiness. If the agent doesn't recognize the situation as flakiness — which is exactly the failure mode the rule is supposed to prevent — the rule never fires.

**Sharper test:** does the rule trigger on observable artifacts in the file system / commit history / tool-call log, or does it trigger on the agent's interpretation of what's happening? The former is enforceable. The latter is hope.

## How to apply these in a harness review

For each existing rule and each proposed addition:

1. Run all five questions
2. Score each as **strong**, **weak**, or **broken**
3. Strong: keep / ship
4. Weak: rewrite to address the failing dimension OR fold into an adjacent rule
5. Broken: delete (yes, even if it has been there a while)

The bias should be toward fewer, sharper, less-circumventable rules — not more. A harness with 50 weak rules enforces less than a harness with 10 strong ones.

## Cross-references

- `~/.claude/CLAUDE.md` — Generation 4/5 enforcement framing
- `rules/diagnosis.md` — exhaustive diagnosis discipline (the rule that should have caught the 2026-04-25 incident but didn't)
- `agents/harness-reviewer.md` — the adversarial review agent. Should apply these five questions explicitly.
- `docs/harness-architecture.md` — full inventory of mechanisms to audit against
