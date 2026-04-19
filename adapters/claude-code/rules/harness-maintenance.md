# Harness Maintenance Rules

When modifying ANY file in `~/.claude/` (agents, rules, hooks, docs, templates, scripts, pipeline-templates):

## 1. Default to Global
Changes to agents, rules, hooks, docs, and templates are **global by default**. Only place a file in a project's `.claude/rules/` when the rule genuinely does not apply to other projects (e.g., project-specific API conventions, project-specific DB migration patterns).

If you're unsure whether a rule is project-specific or global: make it global. It's easier to override one project than to remember to copy a rule into every project.

**Never duplicate a global rule into a project directory.** If a project needs a slightly different version, either:
- Make the global version flexible enough to cover both cases, OR
- Create a project-level rule that only contains the delta (the project-specific additions)

## 2. Commit to neural-lace
After modifying `~/.claude/`, commit the change to the `neural-lace` repo:
```bash
cd ~/claude-projects/neural-lace/adapters/claude-code
# Copy the changed file(s) from ~/.claude/ to the repo
cp ~/.claude/<path> ./<path>
git add . && git commit -m "<type>: <description>"
```

On Windows (where install.sh copies instead of symlinks), `~/.claude/` and `neural-lace/adapters/claude-code/` are independent copies. Changes to one do NOT automatically appear in the other. You must manually sync.

**After syncing, verify with a diff — don't trust your memory of what changed:**
```bash
for dir in agents rules docs hooks templates; do
  [ -d "$HOME/.claude/$dir" ] && [ -d "$HOME/claude-projects/neural-lace/adapters/claude-code/$dir" ] || continue
  for f in "$HOME/.claude/$dir"/*; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    if [ ! -f "$HOME/claude-projects/neural-lace/adapters/claude-code/$dir/$base" ]; then
      echo "MISSING from repo: $dir/$base"
    elif ! diff -q "$f" "$HOME/claude-projects/neural-lace/adapters/claude-code/$dir/$base" > /dev/null 2>&1; then
      echo "DIFFERS: $dir/$base"
    fi
  done
done
```
If this outputs anything, you missed something. Fix it before pushing.

## 3. Update Architecture Doc
Update `~/.claude/docs/harness-architecture.md` when:
- A file is **added, removed, or renamed** — add/remove from the relevant table
- A file's **scope or purpose changes significantly** — update the description column (e.g., adding a major new section to a rule file means the one-line description should reflect the new scope)

Skip the update only for minor content tweaks that don't change what the file covers.

## 4. No Project-Level Rule Copies
Do not copy global rules into project `.claude/rules/` directories. They drift immediately and create confusion. The only files that belong in project `.claude/rules/` are:
- Rules that reference project-specific paths, conventions, or tools
- Rules that override or extend a global rule for that project only

If you find stale copies during a session, delete them (the global version will apply automatically).
