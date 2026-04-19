# Codex Adapter

**Status**: Planned for v1.5

This adapter will translate Neural Lace's Layer 0 principles and Layer 1 patterns into Codex-native configuration (AGENTS.md, codex.json).

## Why Codex First

Codex is architecturally closest to Claude Code — both use file-based configuration, support agent definitions, and have tool interception mechanisms. This makes it the best candidate to validate that Layer 0/1 is truly tool-agnostic.

## Expected Structure

```
codex/
  AGENTS.md          — Agent definitions in Codex format
  codex.json         — Tool configuration
  install.sh         — Deploys from neural-lace to Codex config location
  risk-engine.py     — Risk engine adapter for Codex's interception mechanism
```
