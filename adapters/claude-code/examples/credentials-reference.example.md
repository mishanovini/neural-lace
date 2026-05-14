# Credentials Reference — <your-machine-or-username>

> **Read me when:** you need a credential and want to know which convention is in play. This doc points at established conventions; it does NOT duplicate or reinvent them.

Last updated: YYYY-MM-DD

---

## The convention

Pick whichever describes how credentials actually flow on your machine. Delete the sections that don't apply.

### Option A — Central vault (1Password / Doppler / Infisical / Bitwarden / etc.)

**If you use a vault**, the inventory becomes very small:

- **Source of truth:** `<vault tool>` (e.g., 1Password vault `<vault-name>`)
- **CLI:** `<op | doppler | infisical | bw>`
- **To pull credentials into a project:** `<canonical pull command>` (e.g., `op inject -i .env.template -o .env.local`, `doppler run -- npm run dev`, `infisical run -- npm run dev`)
- **To rotate:** edit the value in `<vault tool>`'s UI / CLI; consuming projects pick up the new value on next `<pull|run>`.

### Option B — Vercel Env + per-repo `.env.local` (no central vault)

If your stack is Vercel-deployed and you don't use a central vault:

1. **Production source of truth:** Vercel Environment Variables per project (set via Vercel dashboard or `vercel env add`)
2. **Local dev values:** `.env.local` in each repo (gitignored)
3. **Schema / key reference:** `.env.example` in each repo (committed; lists expected keys + required-vs-optional comments)
4. **Runtime validation:** project-internal config module (often `src/lib/config/index.ts` with Zod / valibot / similar; throws at boot if required vars missing)

**To populate `.env.local`:**
- Hand-edit using `.env.example` as the schema reference, OR
- `cd <project> && npx vercel link` (one-time) then `npx vercel env pull .env.local`

**To rotate a service token:**
1. Generate new value in provider dashboard
2. Update Vercel Env (`npx vercel env add <KEY> production` or via Vercel dashboard)
3. Update local `.env.local` either by hand or `npx vercel env pull .env.local`
4. Repeat per project if multiple consumers

---

## CLI tools — globally authenticated at standard paths (NOT in env files)

These are the bits a session needs to know about because they're outside the env-file convention. Document only the tools you actually have authenticated.

| Tool | Where the credential lives | Verify | Notes |
|---|---|---|---|
| `gh` | OS keychain | `gh auth status` | <which account is active; switch with `gh auth switch -u <user>`> |
| `claude` (Claude Code) | `~/.claude.json` | the running session itself | Re-auth via `claude login` if expired |
| git over SSH | `~/.ssh/id_<key-name>` | `ssh -T git@github.com` | Document any `~/.ssh/config` aliases (e.g., `Host github-work`) |
| `<other CLI>` | `<path or "OS keychain">` | `<verify command>` | <notes> |

Common candidates to consider: Trigger.dev, Vercel CLI, Netlify, Cloudflare wrangler, Fly, Railway, AWS, gcloud, doctl, Turso, Docker registry auth, npm registry tokens.

---

## CLI tools — token cached but env injection required

Some CLIs store tokens in `~/.<service>/...` but DO NOT auto-pick them up. Document those plus the canonical `export` line so sessions don't rediscover.

| Tool | Cache location | Canonical setup line |
|---|---|---|
| `<example: npx supabase>` | `~/.supabase/tokens/<account-name>` | `export SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/tokens/<account-name>)` |

---

## How sessions should USE this reference

1. **Need a service API key (Anthropic, OpenAI, Twilio, Resend, etc.)?** It's in the project's `.env.local` (Option B) or the vault (Option A). Don't `cat` env files in agent context; use the project's runtime (`npm run dev`, `node --env-file=.env.local <script>`, `npx tsx --env-file=.env.local <script>`).
2. **Need a key list for a project?** Read the project's `.env.example` (Option B) or the vault entry (Option A).
3. **Need to invoke a CLI tool?** Check the "globally authenticated" table. If listed: just use it. If `npx <tool>` returns Unauthorized, check the "token cached but env injection required" table.
4. **About to ask the user to authenticate something?** Re-read this doc first.

---

## What this reference does NOT do

- It does NOT enumerate every env var in every project. That's what each project's `.env.example` is for.
- It does NOT store credential values.
- It does NOT define a new credential-management system. It documents which existing convention is in play.

---

## Audit history

- **YYYY-MM-DD** — initial reference doc.
