# Secret Hygiene — Three-Layer Defense Against Credential Leaks

**Classification:** Hybrid. The discipline of "no secrets in source, no `.env*` committed, no MCP-config files committed" is Pattern (the agent and user self-apply). The mechanical layers are:

- **Layer 1 — Global gitignore** at `~/.config/git/ignore` (or `$XDG_CONFIG_HOME/git/ignore`): pattern-block prevents `git add .` from staging known leak-vector files. Per-machine config, not shipped by the harness installer.
- **Layer 2 — Global pre-push scanner** at `<neural-lace>/adapters/claude-code/hooks/pre-push-scan.sh`, wired in via `git config --global core.hooksPath` pointed at `<neural-lace>/adapters/claude-code/git-hooks/`. Runs on every push from every repo on this machine, scans the diff being pushed against 18 built-in credential regexes + `~/.claude/sensitive-patterns.local` (personal) + `~/.claude/business-patterns.d/*.txt` / `~/.claude/business-patterns.paths` (team-shared).
- **Layer 3 — Remote-side secret scanning** (e.g., GitHub Advanced Security): alerts on commits that reach the remote. Last-line defense if Layers 1+2 are bypassed (e.g., `--no-verify`, accidental public clone, fork by another user).

## Why this rule exists

AI dev-tools (IDE assistants, MCP clients, agentic coding tools) commonly write machine-local config files into repo subdirectories. A casual `git add .` stages them; a `git commit -am` ships them. The tools' docs typically don't mention the file is gitignore-worthy. Without Layer 1, every fresh AI-tool installation creates a new leak vector — and these files routinely contain bearer tokens to downstream services (database pooler URLs, API keys, OAuth refresh tokens).

The three layers are sized so each one independently catches the failure mode:

- Layer 1 prevents `git add` from staging the file (you'd have to `git add -f` to override).
- Layer 2 catches anything that DID get staged and committed, before it reaches a remote.
- Layer 3 catches anything that reached a remote (e.g., if `--no-verify` was used).

## Layer 1 — Global gitignore patterns

The file at `~/.config/git/ignore` is Git's XDG-fallback global gitignore (active when `core.excludesfile` is unset). Five categories of patterns to block:

1. **Harness-local** — `**/.claude/settings.local.json`, `**/.claude/local/` (per-machine Claude Code config).
2. **AI dev-tool MCP configs** — `**/*.mcp.json`, `**/mcp-settings.json`, plus tool-specific filenames (Cursor's `mcp.json`, Claude Desktop's `claude_desktop_config.json`, Cline/Roo settings, Windsurf rules).
3. **AI dev-tool runtime / cache dirs** — `.codeium/`, `.continue/`, `.aider.conf.yml`, `.cline/`, `.roo/`, `.augment/`.
4. **IDE-emitted secret-bearing files** — `**/.idea/workspace.xml`, `**/.idea/dataSources.local.xml`, `**/.zed/settings.json`.
5. **Environment files outside the standard `.env*` set** — `*.env.private`, `.envrc.local`, `*.secrets`, `secrets.local.*`.

The canonical reference file for this machine is `~/.config/git/ignore` itself — each category and pattern is annotated inline. To verify a pattern matches a specific path in any repo:

```bash
git check-ignore -v <path>
```

The verifier returns the line in the ignore file that matched, or non-zero exit if no pattern matches.

### Adding a new pattern

Edit `~/.config/git/ignore` directly. The file is per-machine — propagation to other machines is manual (copy the file, or apply the patterns documented in the rule). Verify with `git check-ignore -v <path>` after editing.

### Force-tracking an ignored file

When a sanitized `.example` variant of an ignored file SHOULD be tracked (e.g., `claude_desktop_config.example.json`), prefer renaming with `.example` suffix rather than `git add -f` — the suffix is self-documenting. If `-f` is genuinely required, do it once during initial setup and document why in the repo's README.

## Layer 2 — Pre-push scanner wiring

**Architecture:** `git config --global core.hooksPath` is set to `<neural-lace>/adapters/claude-code/git-hooks/`. The `pre-push` file in that directory is a dispatcher that invokes the scanner at `<neural-lace>/adapters/claude-code/hooks/pre-push-scan.sh` for every push from every repo on this machine.

### Override-aware verification

A per-repo `core.hooksPath` (`git config --local core.hooksPath`) suppresses the global one. Two common reasons a repo overrides:

- **Default-redundant override** — someone or some tool ran `git config core.hooksPath .git/hooks` (the Git default). This suppresses the global hooksPath without adding any per-repo benefit. Fix: `git config --local --unset core.hooksPath`.
- **Husky-managed** — repos using Husky for git hooks (commonly to run `lint-staged` on pre-commit) install with `core.hooksPath = .husky/_`. This is load-bearing and should NOT be unset. Fix: add `.husky/pre-push` that delegates to the neural-lace scanner (see below).

### Audit command

To audit override status across all repos in a directory:

```bash
cd <repos-parent-dir> && for d in */; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  override=$(cd "$d" && git config --local --get core.hooksPath 2>/dev/null)
  [ -n "$override" ] && echo "$d: OVERRIDES with $override" || echo "$d: uses global (OK)"
done
```

Any repo reporting OVERRIDES needs case-by-case wiring per the two scenarios above.

### Husky-using repos — pre-push delegate pattern

For any repo where Husky is load-bearing, add `.husky/pre-push` that delegates to the neural-lace scanner. The file is committed so the wiring survives fresh clones:

```bash
#!/usr/bin/env bash
# Husky pre-push — delegates to the neural-lace credential scanner.
SCANNER="$HOME/claude-projects/neural-lace/adapters/claude-code/hooks/pre-push-scan.sh"
[ -f "$SCANNER" ] && bash "$SCANNER" "$@" || echo "WARNING: scanner not found" >&2
```

Make it executable (`chmod +x .husky/pre-push`) and commit so the protection survives fresh clones.

### Adding a new credential pattern to the scanner

The scanner loads patterns from three sources merged in order: built-in (defined inline in `pre-push-scan.sh`), `~/.claude/sensitive-patterns.local` (personal — never committed), and `~/.claude/business-patterns.d/*.txt` or `~/.claude/business-patterns.paths` (team-shared via symlinks or path-pointer file). Format per line is `Description|REGEX`. Add new patterns to whichever source matches the audience.

To test that a new pattern blocks correctly, invoke the scanner directly with synthetic stdin in git pre-push format (`<local_ref> <local_sha> <remote_ref> <remote_sha>`) against a real commit range that contains the test pattern. See `pre-push-scan.sh` source for the in-process invocation pattern.

## Layer 3 — Remote-side secret scanning

Most modern Git hosts (GitHub, GitLab) offer built-in secret scanning that runs server-side on every push and creates alerts for matches against hundreds of known credential providers. Enable it organization-wide. It catches:

- Credentials that bypass Layer 2 via `--no-verify`
- Credentials in repos that lack the local hook wiring
- Public-fork scenarios

For some providers (e.g., AWS, Stripe, Anthropic on GitHub), scanning is partner-integrated: when a known-pattern token is detected in a public commit, the provider auto-revokes the credential. For private repos, the alert is in-org only.

**Audit and response.** Check `https://<host>/<org>/<repo>/security/secret-scanning` per repo to see active alerts. Alerts left unaddressed are themselves a leak — they confirm a credential was pushed and survive in history even if the commit is force-reverted. The correct response to any alert is: (a) revoke the credential at the provider, (b) rotate any downstream usage, (c) close the alert.

## Cross-references

- `~/.claude/rules/security.md` — broader credentials/secrets policy, public-repo prohibition, software-install safety.
- `~/.claude/rules/harness-hygiene.md` — what NEVER ships in the harness kit itself (sister rule for kit-vs-instance separation).
- `~/.claude/rules/gate-respect.md` — when a gate (including the pre-push scanner) blocks, the protocol is diagnose-then-fix-then-bypass-as-last-resort.
- `<neural-lace>/adapters/claude-code/hooks/pre-push-scan.sh` — the canonical scanner source.
- `<neural-lace>/adapters/claude-code/git-hooks/pre-push` — the global dispatcher.
- `<neural-lace>/docs/business-patterns-workflow.md` — team-shared sensitive pattern setup guide.

## Enforcement summary

| Layer | What it enforces | File / mechanism |
|---|---|---|
| 1 (gitignore) | Prevents `git add .` from staging leak-vector files | `~/.config/git/ignore` (per-machine; documented patterns above) |
| 2 (pre-push) | Blocks `git push` if staged-commit diff matches a credential regex | `<neural-lace>/adapters/claude-code/hooks/pre-push-scan.sh` invoked via global `core.hooksPath` |
| 2 (Husky parity) | Husky-using repos delegate to the neural-lace scanner | `.husky/pre-push` in repos that override `core.hooksPath` for lint-staged |
| 3 (remote) | Alerts on credentials that reach the remote | Host-provided secret scanning (e.g., GitHub Advanced Security) |
| Pattern | The agent never hardcodes secrets in source, never commits `.env*`, treats MCP/IDE config files as machine-local | self-applied per `security.md` and this rule |

The three mechanical layers are independent — bypassing one (e.g., `--no-verify`) does not bypass the others. The Pattern layer is what makes the mechanical layers rare-fire rather than always-fire.

## Scope

This rule applies on any machine where `git config --global core.hooksPath` points at the neural-lace `git-hooks/` dispatcher AND `~/.config/git/ignore` contains the documented pattern set. Both are per-machine config and are NOT installed by `install.sh` (`install.sh` syncs the harness kit; the machine-level wiring is documented setup that the operator runs once per machine).

For a fresh machine setup:
1. Install neural-lace per the install convention.
2. Run `git config --global core.hooksPath ~/claude-projects/neural-lace/adapters/claude-code/git-hooks/`.
3. Copy or recreate `~/.config/git/ignore` with the patterns documented in "Layer 1" above.
4. Verify with `git check-ignore -v <leak-vector-path>` (should match).
5. Audit per-repo `core.hooksPath` overrides per the audit command in "Layer 2."
