---
description: Switch automation mode between full-auto and review-before-deploy
argument-hint: <full-auto|review|status> [--project]
---

# Automation Mode

Switch the harness's automation mode between `full-auto` (Claude auto-approves routine actions) and `review-before-deploy` (Claude pauses before deploy-adjacent actions for human review), or print the current effective mode.

Given the user's arguments `$ARGUMENTS`, follow this procedure exactly.

## Step 1 — Parse arguments

Split `$ARGUMENTS` on whitespace. Extract:

- `MODE_ARG` = first token (e.g. `full-auto`, `review`, `review-before-deploy`, `status`)
- `PROJECT_FLAG` = true if any remaining token equals `--project`, else false

Valid `MODE_ARG` values:

- `full-auto`
- `review` (alias for `review-before-deploy`)
- `review-before-deploy`
- `status`

If `MODE_ARG` is empty or not one of the above, print usage and stop:

```
Usage: /automation-mode <full-auto|review|status> [--project]

  full-auto             Auto-approve routine actions.
  review                Pause before deploy-adjacent actions for human review.
                        (Alias: review-before-deploy)
  status                Print current effective mode.

  --project             Write the mode to <project>/.claude/automation-mode.json
                        instead of ~/.claude/local/automation-mode.json.
```

Then return without modifying anything.

## Step 2 — Resolve target file

- **Global file**: `~/.claude/local/automation-mode.json`
- **Project file**: `.claude/automation-mode.json` (relative to the current working directory)

If `PROJECT_FLAG` is true, the target file is the project file. Otherwise, the target file is the global file.

The example/seed file lives at `adapters/claude-code/examples/automation-mode.example.json` in the neural-lace harness repo. If you cannot resolve that path from the current working directory, fall back to an inline seed (see Step 4).

## Step 3 — Handle `status`

If `MODE_ARG` is `status`:

1. Read the global file at `~/.claude/local/automation-mode.json`.
   - If it does not exist, report: `Global: (not set — default is review-before-deploy)`.
   - Otherwise, extract `.mode` and `.deploy_matchers` with `jq` and report them.

2. Check whether `.claude/automation-mode.json` exists in the current working directory.
   - If it exists, read it and report: `Project override: mode=<mode>, deploy_matchers=<array>`.
   - If it does not exist, report: `Project override: (none)`.

3. Output format:

   ```
   Automation mode status
   ----------------------
   Global:           mode=<mode>
                     deploy_matchers=<comma-separated list>
   Project override: <mode or "(none)">

   Effective mode:   <project override if present, else global, else "review-before-deploy">
   ```

4. Stop.

## Step 4 — Apply a mode change

If `MODE_ARG` is `full-auto`, `review`, or `review-before-deploy`:

1. **Normalize the mode**: if `MODE_ARG` is `review`, rewrite it to `review-before-deploy`. The final normalized value (`full-auto` or `review-before-deploy`) is `NEW_MODE`.

2. **Verify `jq` is available**. Run `command -v jq`. If it is not found, stop and report:

   ```
   Error: `jq` is required but was not found on PATH. Install jq (https://stedolan.github.io/jq/) and retry.
   ```

3. **Ensure the target directory exists**:

   - Global: `mkdir -p ~/.claude/local`
   - Project: `mkdir -p .claude`

   If `mkdir` fails (e.g. permission denied), stop and report the error with the target path.

4. **Load the existing target file, or seed a new one**:

   - If the target file exists and parses as JSON (`jq empty <file>` exits 0), use it as the base.
   - If the target file does not exist or is not valid JSON, seed from `adapters/claude-code/examples/automation-mode.example.json` if readable. If that path cannot be resolved, use this inline seed:

     ```json
     {
       "version": 1,
       "mode": "review-before-deploy",
       "deploy_matchers": [
         "git push",
         "gh pr merge",
         "gh repo create",
         "supabase db push",
         "vercel deploy",
         "npm publish"
       ]
     }
     ```

5. **Write the updated file atomically with `jq`**. Use a temp file in the same directory, then move it over the target:

   ```bash
   TARGET="<resolved target path>"
   TMP="${TARGET}.tmp"
   jq --arg mode "<NEW_MODE>" '.mode = $mode' "$TARGET" > "$TMP" && mv "$TMP" "$TARGET"
   ```

   (If the target did not exist, first write the seed JSON to `$TARGET`, then run the `jq` line above against it. This keeps `deploy_matchers` intact for existing files and seeded for new ones.)

   If `jq` fails or `mv` fails, stop and report the error; do not leave a partial file. Remove `$TMP` if it still exists.

6. **Confirm to the user**:

   ```
   Automation mode set to <NEW_MODE> (<scope>).
   File: <resolved target path>
   ```

   Where `<scope>` is `project` if `PROJECT_FLAG` was true, else `global`.

7. Stop.

## Error handling summary

- Unrecognized `MODE_ARG`: print usage, exit without changes.
- Missing `jq`: stop with install instructions.
- Permission error on `mkdir` or write: stop and report the path + error; do not retry blindly.
- Invalid existing JSON in target: seed a fresh file rather than corrupting further; mention the reseed in the confirmation message.

## Notes

- Never print the contents of `deploy_matchers` in a way that suggests they are secrets — they are literal command prefixes, safe to display.
- Do not modify any file other than the resolved target.
- Do not alter the `version` field.
- Do not run `git` commands; this command only edits the mode config file.
