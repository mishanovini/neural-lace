---
name: calibrate
description: Capture a structured calibration entry for an agent (builder or reviewer) when an observed failure or shortcut is noticed. Writes to `.claude/state/calibration/<agent-name>.md` (gitignored, per-machine operational state). Use when the user invokes `/calibrate <agent> <observation-class> <details>`, or when reviewing a session and noticing an agent took a shortcut, hallucinated, or passed-by-default. Periodic roll-up via `/harness-review`.
---

# calibrate

Manual-entry calibration loop. Captures per-agent observations as the manual
bootstrap of the Knowledge Integrator role until telemetry lands
(HARNESS-GAP-11). One entry per observed failure/shortcut/pattern; periodic
roll-up surfaces patterns that warrant prompt or work-shape updates.

This is the operational substrate for Build Doctrine Principle 9 ("Documents
are living; updates propagate on trigger") applied to the harness's own
agents. Every agent's prompt is a living document; calibration entries are
the durable signal that drives propagation.

## When to use

Invoke `/calibrate` when:

- A reviewer agent (e.g., `task-verifier`, `code-reviewer`, `claim-reviewer`)
  returned PASS where it should have returned FAIL — and you can name what it
  missed.
- A builder agent took a shortcut to mark its work complete (e.g., narrowed
  the test, skipped a runtime check, claimed coverage without exercising the
  path).
- An agent hallucinated a capability, file path, or behavior the codebase
  does not have.
- An agent's output drifted from its documented contract (wrong format,
  missing required field, off-by-one severity).
- Any pattern that, if it recurs, would warrant a prompt update or a new
  mechanical gate.

Do NOT use this skill for:

- General bug reports about the codebase under build (those go to
  `docs/backlog.md` or `docs/findings.md` per the findings-ledger rule).
- One-off user corrections that don't generalize (those just get fixed).
- Speculative concerns ("agent X might do Y") — calibrate on observed
  behavior only.

## How to invoke

Three argument forms:

- **Three-arg:** `/calibrate <agent-name> <observation-class> <details>`
- **Two-arg (free-form):** `/calibrate <agent-name> <observation-class>` —
  prompts for details inline.
- **No-arg:** `/calibrate` — prints usage and exits.

Examples:

```
/calibrate task-verifier shortcut "verifier returned PASS without checking the runtime command actually ran; pre-stop catch caught it on the next session"

/calibrate code-reviewer pass-by-default "reviewer returned APPROVE on a 200-line diff in 4 seconds; sibling-instance check missed three uses of the same pattern in adjacent files"

/calibrate end-user-advocate hallucination "advocate's runtime-mode artifact cited a screenshot path that does not exist on disk"
```

## Observation classes

The `observation-class` is a kebab-case label naming the failure shape.
Five canonical classes (use these unless none fit):

- **`shortcut`** — agent took a shortcut to mark work complete (narrowed
  scope, skipped a verification step, picked the easiest exit).
- **`hallucination`** — agent claimed a capability, file, or behavior that
  does not exist or was not exercised.
- **`pass-by-default`** — reviewer agent returned PASS without actually
  reviewing (skim-only, time-budget-limited, returned in suspiciously low
  duration relative to scope).
- **`format-drift`** — agent output did not conform to its documented
  contract (missing field, wrong section heading, malformed evidence
  block).
- **`scope-drift`** — agent went outside its declared scope (touched files
  it should not have, made decisions outside its role's authority).

If none of the five fit, propose a new class in the `details` field
(prefix with `new-class:` so the roll-up reviewer notices). Do not coerce
a misfit observation into one of the five.

## Entry format

The skill writes to `.claude/state/calibration/<agent-name>.md`, creating
the file with a header if missing, and appending one entry per invocation.
File header (written once on creation):

```markdown
# Calibration entries — <agent-name>

Per-agent observations of shortcuts, hallucinations, and format drift.
Manually-captured via `/calibrate`. Roll-up via `/harness-review` Check 12.

Entry shape:
- timestamp (ISO 8601)
- observation-class
- details (1-3 sentences naming what was observed)
- suggested mitigation (1 sentence; what would catch this next time)

```

Per-entry shape:

```markdown
## <ISO 8601 timestamp> — <observation-class>

<details — one to three sentences naming what was observed, with file:line
or commit citation where available>

**Suggested mitigation:** <one sentence proposing what would catch this
next time — a prompt extension, a new mechanical check, a counter-incentive
discipline note, etc.>
```

The skill produces the timestamp itself; the user supplies the
observation-class and details. The skill prompts for the suggested
mitigation if not embedded in the details — keeping the field separate
ensures every entry has an actionable next-step proposal.

## Execution

```bash
#!/bin/bash
set -u

# Args: $1 = agent-name, $2 = observation-class, $3+ = details
AGENT="${1:-}"
CLASS="${2:-}"
shift 2 2>/dev/null || true
DETAILS="${*:-}"

if [[ -z "$AGENT" || -z "$CLASS" ]]; then
  echo "Usage: /calibrate <agent-name> <observation-class> <details>" >&2
  echo "" >&2
  echo "Observation classes (canonical):" >&2
  echo "  shortcut, hallucination, pass-by-default, format-drift, scope-drift" >&2
  echo "" >&2
  echo "Example:" >&2
  echo "  /calibrate task-verifier shortcut \"verifier returned PASS without checking the runtime command\"" >&2
  exit 1
fi

# Validate agent-name: kebab-case, ASCII, <= 60 chars
if [[ ! "$AGENT" =~ ^[a-z0-9-]+$ ]] || [[ ${#AGENT} -gt 60 ]]; then
  echo "calibrate: invalid agent-name '$AGENT' (must be kebab-case ASCII, <= 60 chars)" >&2
  exit 1
fi

# Validate observation-class: kebab-case
if [[ ! "$CLASS" =~ ^[a-z0-9-]+(:.+)?$ ]]; then
  echo "calibrate: invalid observation-class '$CLASS' (must be kebab-case; use 'new-class:<label>' to propose a new class)" >&2
  exit 1
fi

if [[ -z "$DETAILS" ]]; then
  echo "calibrate: details argument is required (one to three sentences)" >&2
  exit 1
fi

# Locate calibration directory (per-working-directory state)
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CALIB_DIR="$REPO_ROOT/.claude/state/calibration"
mkdir -p "$CALIB_DIR"

ENTRY_FILE="$CALIB_DIR/$AGENT.md"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Initialize header on first entry
if [[ ! -f "$ENTRY_FILE" ]]; then
  cat > "$ENTRY_FILE" <<HEADER
# Calibration entries — $AGENT

Per-agent observations of shortcuts, hallucinations, and format drift.
Manually-captured via \`/calibrate\`. Roll-up via \`/harness-review\` Check 12.

Entry shape:
- timestamp (ISO 8601)
- observation-class
- details (1-3 sentences naming what was observed)
- suggested mitigation (1 sentence; what would catch this next time)

HEADER
fi

# Extract suggested mitigation if separated by ' || ' or '\nMitigation: '
# Otherwise leave as TODO so the roll-up surfaces it
if [[ "$DETAILS" == *" || "* ]]; then
  BODY="${DETAILS% || *}"
  MITIGATION="${DETAILS##* || }"
else
  BODY="$DETAILS"
  MITIGATION="(none provided — populate when reviewing entries)"
fi

# Append entry
cat >> "$ENTRY_FILE" <<ENTRY

## $TIMESTAMP — $CLASS

$BODY

**Suggested mitigation:** $MITIGATION
ENTRY

echo "calibrate: appended entry to $ENTRY_FILE"
echo "  agent: $AGENT"
echo "  class: $CLASS"
echo "  timestamp: $TIMESTAMP"
exit 0
```

## Self-test

```bash
# Self-test cases:
# 1. Missing agent → exit 1 with usage
# 2. Invalid agent-name (uppercase) → exit 1
# 3. Missing class → exit 1 with usage
# 4. Missing details → exit 1
# 5. Valid invocation → file created with header + entry
# 6. Second invocation on same agent → file gets new entry, header preserved
# 7. ' || ' separator → mitigation captured separately

# Run from repo root:
TMP=$(mktemp -d)
cd "$TMP" && git init -q

# Case 1
bash ~/.claude/skills/calibrate.md 2>&1 | grep -q "Usage:" && echo "PASS: case 1" || echo "FAIL: case 1"

# Case 5
bash ~/.claude/skills/calibrate.md task-verifier shortcut "verifier returned PASS without runtime check" \
  && [[ -f .claude/state/calibration/task-verifier.md ]] \
  && grep -q "Calibration entries — task-verifier" .claude/state/calibration/task-verifier.md \
  && grep -q "shortcut" .claude/state/calibration/task-verifier.md \
  && echo "PASS: case 5" || echo "FAIL: case 5"
```

The above is illustrative — the skill is not currently structured as a
standalone bash file. The actual self-test runs through `/calibrate`
invocations against a temporary working directory. See the rule
`~/.claude/rules/calibration-loop.md` for the full discipline and how
roll-up consumes the entries.

## State directory layout

```
.claude/state/calibration/
├── task-verifier.md
├── code-reviewer.md
├── plan-evidence-reviewer.md
├── end-user-advocate.md
└── <other-agent-name>.md
```

One file per agent. Files are gitignored (per Decision G.1 in
`docs/decisions/queued-tranche-1.5.md`) — calibration is operational data,
not durable artifact. Promotion to durable artifacts happens via the
Knowledge Integrator role's periodic review, mediated by `/harness-review`
roll-up.

## Roll-up

The `/harness-review` skill (Check 12) reads `.claude/state/calibration/*.md`
and emits a section summarizing:

- Total entry count per agent
- Top-3 most-frequent observation classes per agent (with counts)
- Most-recent entry per class

Patterns that recur across multiple agents (e.g., `pass-by-default` showing
up on three reviewers in one week) are the signal that warrants a
counter-incentive prompt update or a new mechanical gate.

## Honest limitations

- **Entries grow unbounded.** Roll-up reads all; if entry count exceeds
  100 per agent, the harness-review skill warns; archival to a sub-directory
  is deferred to a follow-up task.
- **Discipline-dependent.** No mechanism forces calibration entries to be
  written. The skill just reduces friction. Telemetry-driven mechanization
  is HARNESS-GAP-11, gated on 2026-08.
- **Per-machine state.** Calibration entries are gitignored — they do not
  travel between machines. A user with multiple machines accumulates
  separate streams. Migration to a shared findings-ledger entry (Decision
  G.1 option C) is reversible.

## Related

- `~/.claude/rules/calibration-loop.md` — the discipline this skill
  implements; observation-class semantics; what becomes a prompt update
  vs. a work-shape extension vs. defers to telemetry.
- `~/.claude/skills/harness-review.md` Check 12 — the roll-up consumer.
- `docs/decisions/queued-tranche-1.5.md` G.1, G.2 — decisions backing the
  storage location and manual-vs-mechanized cadence.
- `docs/decisions/026-harness-catches-up-to-doctrine.md` — the framing this
  bootstrap operationalizes.
- `build-doctrine/doctrine/01-principles.md` Principle 9 — Documents are
  living; updates propagate on trigger.
- `build-doctrine/doctrine/02-roles.md` Role 9 (Knowledge Integrator) — the
  doctrinal role this manual loop bootstraps.
