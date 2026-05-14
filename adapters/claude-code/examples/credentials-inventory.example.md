# Credentials Inventory — <your-machine-or-username>

> **Read me when:** you need to invoke a CLI tool or talk to an external service.
> Before assuming credentials are missing or asking the user to authenticate,
> check this file. If the tool is listed here, the auth is already on this
> machine and you just need to know how to use it.

Last updated: YYYY-MM-DD
Last full audit: YYYY-MM-DD

---

## How to use this inventory

Each entry below has six fields:

- **Status** — `authenticated` / `not-authenticated` / `env-only` (no global auth; per-project env vars)
- **Where the credential lives** — concrete path on this machine, or "env file" + which env file
- **Token type** — PAT (Personal Access Token), OAuth session, secret key, SSH key, etc.
- **Works without env** — commands you can run from any cwd without setting env vars first
- **Needs env** — commands that need explicit env setup, with the canonical setup line
- **Refresh policy** — when this expires, who rotates it, how

Conventions:

- Paths use `~/` for `$HOME`.
- "Env files" means `.env.local` (Next.js / Vite / etc.) or `.env` (dotenv).
- NEVER `cat` an env file in agent sessions — read the key list, then use a runtime that injects without echoing (`dotenv -e .env.local -- <cmd>`, `node --env-file=.env.local`, etc.).

---

## CLI tools — globally authenticated

### GitHub CLI (`gh`)

- **Status:** authenticated, <N> account(s)
- **Where the credential lives:** OS keychain (macOS Keychain / Windows Credential Manager / `gh` config dir on Linux)
- **Token type:** OAuth (`gho_*`)
- **Active account:** `<your-active-gh-username>`
- **Other accounts (if any):** `<your-other-gh-username>` — switch via `gh auth switch -u <account>`
- **Works without env:** `gh repo view`, `gh pr create`, `gh pr merge`, `gh issue list`, `gh api`
- **Needs env:** `GH_TOKEN` for CI / scripted contexts only
- **Refresh policy:** OAuth session; user-only via `gh auth login`
- **Verify:** `gh auth status`

### git (SSH + GitHub)

- **Status:** authenticated, <N> key(s)
- **Where the credentials live:** `~/.ssh/id_ed25519_<alias>` (+ `.pub`)
- **SSH config aliases:** see `~/.ssh/config`
- **Token type:** ed25519 SSH keypair
- **Works without env:** `git push`, `git pull`, `git fetch`, `git clone` against either remote (SSH `Host` alias selects key)
- **Refresh policy:** SSH keys do not expire; rotate if leaked
- **Verify:** `ssh -T git@github.com`
- **Note:** `gh` and SSH are independent — switching `gh auth` does NOT switch SSH key

### Claude Code (`claude`)

- **Status:** authenticated (the current session is itself proof)
- **Where the credential lives:** `~/.claude.json`
- **Token type:** Anthropic subscription session
- **Works without env:** all `claude` invocations
- **Needs env:** `CLAUDE_CODE_OAUTH_TOKEN` for CI / `claude --remote` / Routines contexts
- **Refresh policy:** auto-refresh; user-only via `claude login` if expired

### <Your other globally-authenticated CLIs go here>

Example shape for adding a new entry:

```
### <Tool name> (`<binary or invocation>`)

- **Status:** authenticated as <account-or-email>
- **Where the credential lives:** <path on disk or "OS keychain">
- **Token type:** PAT / OAuth / Bearer / SSH key
- **Works without env:** <commands that work bare>
- **Needs env:** <commands that need env, with the canonical setup line>
- **Refresh policy:** <expiration behavior, who rotates, how>
- **Verify:** <command that confirms auth without exposing secret>
```

Common candidates: Vercel (`vercel`), Netlify (`netlify`), Cloudflare (`wrangler`), Fly (`flyctl`), Railway (`railway`), AWS (`aws`), Google Cloud (`gcloud`), DigitalOcean (`doctl`), Turso (`turso`), Docker registries (`docker login` cache), npm (`npmrc` auth tokens), Anthropic console (separate from Claude Code), OpenAI CLI, Trigger.dev (`npx trigger.dev`), Supabase (`npx supabase`), pscale/PlanetScale, etc.

---

## CLI tools — token in `~/` but env injection often needed

Some CLIs store tokens in `~/.<service>/tokens/` but DO NOT auto-pick them up — you must `export` the right token first. Document those here with the canonical export line so sessions don't have to rediscover.

### Example: Supabase (`npx supabase`)

- **Status:** account tokens present at `~/.supabase/tokens/`, but CLI returns `Unauthorized` until `SUPABASE_ACCESS_TOKEN` is exported
- **Where the credentials live:** `~/.supabase/tokens/<account-name>` (one file per account; each file contains a Supabase PAT)
- **Token type:** Supabase PAT (`sbp_*`)
- **Needs env (canonical setup):**
  ```bash
  export SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/tokens/<account-name>)
  ```
- **Per-project anon/service keys:** stored in each project's `.env.local`; DIFFERENT credential from the CLI PAT
- **Refresh policy:** PAT does not expire; rotate via Supabase Dashboard → Account → Access Tokens

---

## API tokens — env-only (in per-project env files)

These have no global CLI auth. Each project sources them from its own env file. Agent sessions should USE them via the project's runtime — never `cat` the env file in agent context.

| Service | Env var(s) | Source of truth (rotate here) | Used by |
|---|---|---|---|
| Anthropic API | `ANTHROPIC_API_KEY` | console.anthropic.com → API Keys | <projects> |
| OpenAI | `OPENAI_API_KEY` | platform.openai.com → API Keys | <projects> |
| Google AI (Gemini) | `GOOGLE_AI_API_KEY` or `GOOGLE_API_KEY` | aistudio.google.com → API Keys | <projects> |
| <Other service> | `<env var name>` | <where to rotate> | <which projects use it> |

---

## Per-project env files (key names only — values redacted)

When a session needs project-specific env, the canonical pattern is:

```bash
cd <project> && npm run dev                            # Next.js loads .env.local automatically
cd <project> && node --env-file=.env.local <script>    # one-off node script
cd <project> && npx tsx --env-file=.env.local <script> # tsx / TypeScript script
cd <project> && set -a; source .env.local; set +a; <cmd>  # explicit injection in bash
```

### `~/<project-path>/.env.local`
```
<KEY_1>  <KEY_2>  <KEY_3>
<KEY_4>  <KEY_5>  <KEY_6>
```
(Add one section per project with its env var key names. Values stay in the file; this inventory lists names only.)

---

## Rotation policy

Different credentials have different rotation cadences and authorities:

| Credential class | Who can rotate | When | How |
|---|---|---|---|
| GitHub OAuth (`gh`) | User only | If expired or after leak | `gh auth login` |
| SSH keys | User only | If leaked | `ssh-keygen` + replace in GitHub Settings → SSH keys |
| Service PATs (Trigger.dev, Supabase, etc.) | User or session | If leaked | Provider dashboard → revoke + new → update local cache |
| API keys (Anthropic, OpenAI, etc.) | User or session | If leaked or quota change | Provider dashboard → create new → update every `.env.local` that uses it |
| Per-project DB / auth keys | User only | Project key rotation event (rare) | Provider dashboard → rotate; update every consumer |

**Rotation discipline for agent sessions:**

1. NEVER rotate a credential the user did not ask you to rotate. Rotation is destructive — old credential dies, every consumer needs the new one, downtime windows matter.
2. WHEN a session rotates a credential at user request, it MUST update this inventory's `Last updated:` field and the affected entry in the same response.
3. WHEN the user adds a NEW service, the integrating session must add a row to this inventory in the same commit as the integration code.

---

## What this inventory does NOT contain

- **Actual credential values.** Only WHERE they live and HOW to use them.
- **Per-project build-time env vars** (e.g., `VERCEL_*` populated only inside the Vercel runner)
- **`~/.claude/local/` config files** — those are session/account config, not service credentials
- **MCP server credentials** — those live in `~/.claude/mcp-needs-auth-cache.json` and per-server config

---

## How sessions should USE this file

1. **Before running any CLI command that talks to an external service**, check: "is this tool listed above?" If yes, use the documented invocation pattern. If no, ASK the user before assuming auth is missing.
2. **Before saying "we don't have access to X" to the user**, grep this file. The answer is often "yes we do, here's how."
3. **If `npx <tool>` returns Unauthorized** and the tool IS listed here, re-read the entry's `Needs env` section — the canonical export line is documented.
4. **If you find a credential on this machine that's NOT listed here**, add it (after confirming with the user) so the next session sees it.
5. **If a documented credential turns out to be wrong** (expired, moved, format changed), update the entry in the same response — never leave a stale entry knowing it's stale.

---

## Audit history

- **YYYY-MM-DD** — <one-line description of what changed>
