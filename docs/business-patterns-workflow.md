# Business Patterns Workflow

How to share sensitive patterns across a team without leaking them into any public repo.

## The Problem

Every developer on a team needs to block the same sensitive patterns (internal project IDs, API endpoints, org identifiers) in their git pushes. But:

- The patterns themselves can't live in a public repo (that would leak them)
- Each developer manually maintaining their own list leads to drift
- New team members need to bootstrap fast without missing patterns

## The Solution

Store team patterns in a **private repo** (e.g., `security-docs`), with each developer symlinking the patterns file into a known location. The scanner auto-loads anything in that location. Updates flow via normal `git pull`.

## Architecture

```
┌────────────────────────────────────────┐
│  Private team repo: security-docs       │
│   ├── business-patterns.txt  ← single source of truth
│   └── ONBOARDING.md                      │
└────────────────┬───────────────────────┘
                 │ clone + symlink
                 ▼
┌────────────────────────────────────────┐
│  Each developer's machine                │
│   ~/.claude/business-patterns.d/         │
│     └── <org>.txt              ← symlink → clone
└────────────────┬───────────────────────┘
                 │ scanner reads
                 ▼
┌────────────────────────────────────────┐
│  Pre-push scanner                        │
│  (neural-lace/adapters/claude-code/hooks/pre-push-scan.sh)  │
│  Loads ALL files in business-patterns.d/ │
└────────────────────────────────────────┘
```

## Why This Works

**Single source of truth**: The canonical patterns live in ONE place (the private repo). Team members all read the same file.

**No drift**: Updates happen in one commit. A `git pull` in the patterns repo updates every developer's scanner immediately — no reinstall needed because the file is symlinked.

**Public-repo safe**: The patterns file is never pushed to any public repo. The scanner has a safelist that exempts files named `business-patterns.txt` from content scanning, so even the patterns file itself can be pushed to its private home without the scanner tripping on itself.

**Multi-tenant**: A developer can have multiple team pattern files (one per org they work with) — each lives as a separate symlink in `business-patterns.d/`.

**Personal patterns stay personal**: `~/.claude/sensitive-patterns.local` is for patterns you don't want to share with the team (e.g., personal cloud accounts). The scanner loads both in parallel.

## Setup (Team Lead / First Install)

**1. Create the private repo**

```bash
gh repo create <org>/security-docs --private --description "Security audits and shared patterns"
```

The public-repo block hook in `settings.json.template` prevents accidentally creating this as public.

**2. Add the patterns file with the magic basename**

The file must be named exactly `business-patterns.txt` — that's what the scanner safelists.

```bash
cd security-docs
cat > business-patterns.txt << 'EOF'
# <Org Name> sensitive patterns
# Format: DESCRIPTION|REGEX
# Lines starting with # are comments.

Internal API endpoint|api\.internal\.<org>\.com
Internal database host|db\.internal\.<org>\.com
EOF
git add business-patterns.txt
git commit -m "chore: initial team sensitive patterns"
git push
```

**3. Add ONBOARDING.md to the repo**

Walk new team members through the setup.

**4. Grant team members access**

```bash
gh api --method PUT /repos/<org>/security-docs/collaborators/<username> -f permission=push
```

## Setup (New Team Member)

**1. Install the harness** (if not done already)

```bash
git clone <neural-lace-url> ~/claude-projects/neural-lace
cd ~/claude-projects/neural-lace
./install.sh
```

This creates `~/.claude/business-patterns.d/` and sets up the global git hook.

**2. Clone the team's private patterns repo**

```bash
mkdir -p ~/claude-projects/<org>
cd ~/claude-projects/<org>
git clone https://github.com/<org>/security-docs.git
```

**3. Symlink the team patterns file**

```bash
ln -s ~/claude-projects/<org>/security-docs/business-patterns.txt \
      ~/.claude/business-patterns.d/<org>.txt
```

**4. Verify**

```bash
ls -l ~/.claude/business-patterns.d/
# Should show: <org>.txt -> /home/.../security-docs/business-patterns.txt
```

**5. Test the scanner** (deliberately trigger a block)

```bash
cd /tmp && mkdir test && cd test
git init
echo "<some pattern from business-patterns.txt>" > trigger.txt
git add trigger.txt && git commit -m "test"
git push origin main 2>&1 | grep BLOCKED
```

## Adding a New Pattern

1. Edit `security-docs/business-patterns.txt`
2. Commit with clear message: `chore: add <description> to blocked patterns`
3. Push
4. Announce in team chat: "Please `git pull` in security-docs — new pattern added"
5. Everyone pulls. Scanner picks up the new pattern on next push automatically.

## Removing a Pattern

Same workflow — edit, commit, push, announce. Old matches in git history are not affected (the scanner only blocks NEW pushes).

## Handling False Positives

If a legitimate push gets blocked by a team pattern:

1. **Short-term**: `git push --no-verify` for this one push
2. **Long-term**: Open a discussion with the team about whether to refine the regex
3. If the pattern is genuinely too broad, propose a tighter regex in a PR to security-docs

## Why the Scanner Doesn't Block business-patterns.txt Itself

The scanner scans the diff of each file being pushed and matches patterns against added lines. If `business-patterns.txt` contained raw patterns and got scanned normally, the scanner would match its own patterns against itself and block every push.

To solve this, the scanner has a **content-scan exemption list**. Any file whose basename is exactly `business-patterns.txt` is skipped for content scanning (the filename is still checked against sensitive filename patterns). See `hooks/pre-push-scan.sh` function `is_content_scan_exempt`.

This means:
- ✅ You can edit and push `business-patterns.txt` freely
- ❌ You cannot hide a credential in a file named `business-patterns.txt` to bypass the scanner (the safelist is path-based, and credential detection still runs in all other files)

## Security Considerations

**Q: What if `security-docs` accidentally becomes public?**
A: The public-repo creation hook in `neural-lace/adapters/claude-code/settings.json.template` blocks `gh repo create --public` and `gh repo edit --visibility public`. The `rules/security.md` also instructs Claude Code to never make repos public without explicit user authorization in the current message. Human error is still possible but multiple layers protect against it.

**Q: What if someone commits a real credential to security-docs by accident?**
A: The scanner still runs on security-docs itself, catching the credential before it pushes (the safelist only exempts files named `business-patterns.txt`, not the whole repo).

**Q: Why not just use a single unified patterns file?**
A: Separation of concerns. Personal patterns shouldn't be shared; team patterns need to be versioned and synced. The `business-patterns.d/` directory lets you layer multiple sources cleanly.

**Q: Why symlinks instead of copying?**
A: Copies drift. Symlinks mean `git pull` in security-docs immediately updates the scanner — zero reinstall, zero chance of stale pattern files.
