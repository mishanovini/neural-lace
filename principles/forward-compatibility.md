# Forward Compatibility: Designing for a Changing World

## What This Principle Covers

How to build a harness that survives the rapid evolution of AI tools, models, and development paradigms. The AI landscape will look fundamentally different in 12 months. Neural Lace must be designed so that change is absorbed by thin adapter layers while core principles and patterns remain stable.

## Core Premise

**Principles outlive tools.** The principle "destructive operations require confirmation" will be true regardless of whether the tool is Claude Code, Codex, Cursor, Gemini, or something that doesn't exist yet. The enforcement mechanism (a PreToolUse hook, a .cursorrules directive, an AGENTS.md policy) will change with every tool version. Design accordingly.

## The Abstraction Stack

```
┌─────────────────────────────────┐
│  Layer 0: PRINCIPLES            │  ← Changes rarely (years)
│  What should be true            │     "Secrets must never be committed"
├─────────────────────────────────┤
│  Layer 1: PATTERNS              │  ← Changes occasionally (months)
│  How to check for it            │     "Scan diffs for credential patterns"
├─────────────────────────────────┤
│  Layer 2: ADAPTERS              │  ← Changes frequently (weeks)
│  Tool-specific implementation   │     "PreToolUse hook runs pre-push-scan.sh"
├─────────────────────────────────┤
│  Layer 3: PROJECT               │  ← Changes per project
│  Project-specific context       │     "Also scan for SUPABASE_SERVICE_ROLE"
└─────────────────────────────────┘
```

**The rule**: information at each layer should only depend on the layer below it, never above. Layer 0 never mentions a specific tool. Layer 1 never mentions a specific tool's config format. Layer 2 translates patterns into native config. Layer 3 adds project context.

## What Survives Tool Changes

These survive any change to the AI tool landscape:

- **Risk dimensions** (reversibility, blast radius, sensitivity, authority escalation) — these describe properties of actions, not properties of tools
- **Permission tiers** (silent allow, log, confirm, block) — these describe human-AI interaction patterns
- **Trust accumulation** — the concept that reliability earns autonomy is universal
- **Evaluation discipline** — the need to verify before shipping is permanent
- **Security principles** — defense in depth, credential scanning, least privilege
- **Telemetry patterns** — what to observe, even if how to observe changes

## What Doesn't Survive

These will break when tools change:

- **Config file formats** — `settings.json` structure, `.cursorrules` syntax, `AGENTS.md` format
- **Hook APIs** — how tools intercept actions, what environment variables are available
- **Agent definition formats** — how sub-agents are declared and invoked
- **CLI interfaces** — command names, flag syntax, output formats
- **Model behavior assumptions** — what a model understands, how it interprets instructions

**This is fine.** These all live in Layer 2 (adapters), which is designed to be rewritten per tool.

## Adaptation Rules

### Rule 1: Write Principles First, Enforcement Second

When creating a new rule or policy:
1. Write the principle in Layer 0 ("what should be true and why")
2. Write the pattern in Layer 1 ("what to check and when")
3. Write the enforcement in Layer 2 ("how to check it in this specific tool")

If you skip steps 1-2 and go straight to enforcement, you create a rule that dies with its tool.

### Rule 2: Use Abstract Categories, Not Tool-Specific Names

Risk profiles use abstract tool categories:
- `shell` not `Bash`
- `file-edit` not `Edit`
- `file-read` not `Read`
- `web-request` not `WebFetch`

Adapters translate between abstract categories and tool-native names.

### Rule 3: Store Data in Tool-Agnostic Formats

- Risk profiles: JSONL (universally readable)
- Telemetry events: JSONL with a stable schema
- Trust ledger: JSON
- Principles and patterns: Markdown

No tool-specific data formats in Layer 0 or Layer 1.

### Rule 4: Design Interfaces, Not Implementations

The adapter contract is an interface. Any tool that can:
1. Intercept actions before execution
2. Classify the action into abstract categories
3. Display confirmation prompts to the user
4. Emit telemetry events

...can be a Neural Lace adapter. The interface is small. The implementation varies per tool.

### Rule 5: Version Layers Independently

Layer 0 changes are major versions (1.0 → 2.0). Layer 1 changes are minor versions (1.0 → 1.1). Layer 2 changes are patch versions or independent version tracks per adapter. A Layer 2 change should NEVER require a Layer 0 change.

### Rule 6: Anticipate Model Capability Shifts

As AI models improve:
- **More capable models** → higher trust ceilings, faster trust accumulation
- **New modalities** (vision, code execution, web browsing) → new risk dimensions or new action categories, but the scoring framework stays
- **Multi-model systems** → trust is per-model, not per-session
- **Real-time collaboration** → trust accounting must handle concurrent sessions

Design the trust and risk models with extension points for capabilities that don't exist yet.

## Migration Patterns

### When a New Tool Arrives

1. Create a new adapter directory (`adapters/<tool-name>/`)
2. Map the tool's action interception mechanism to the adapter interface
3. Translate tool-native action descriptors to abstract categories
4. Implement confirmation UX using the tool's native mechanism
5. Wire telemetry emission to the shared store
6. Run in shadow mode alongside manual testing
7. Graduate after behavioral tests pass

### When a Tool Changes Its API

1. Update only the affected adapter (`adapters/<tool-name>/`)
2. Run behavioral golden tests to verify nothing regressed
3. If the change requires a new abstract category, add it to Layer 1 (minor version)
4. If the change reveals a principle gap, update Layer 0 (major version — rare)

### When the Harness Itself Evolves

1. New principles are additive (existing principles don't change)
2. New patterns extend the classifier chain (existing profiles don't change)
3. New adapters are independent (existing adapters don't change)
4. Telemetry schemas are append-only (new fields, never remove old ones)

## Anti-Patterns to Avoid

- **Tool lock-in**: Writing rules that only make sense in one tool's ecosystem
- **Leaky abstractions**: Layer 0 principles that reference Layer 2 config formats
- **Premature optimization for tools that don't exist**: Don't build a Gemini adapter until Gemini exists as a coding tool; do design the interface so building one is straightforward
- **Coupling telemetry to tool internals**: Telemetry events should describe what happened in abstract terms, not how the tool represented it internally
- **Assuming current model limitations are permanent**: Today's models need detailed instructions; tomorrow's may need only goals. Design for both.
