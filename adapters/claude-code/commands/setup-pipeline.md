# Setup Pipeline

Set up the multi-agent verification pipeline for this project. This creates all the necessary directories, scripts, and configuration for the builder → verifier pipeline.

## Steps

1. Create the pipeline working directory:
   ```
   mkdir -p pipeline scripts
   ```

2. Copy pipeline scripts from global templates:
   ```
   cp ~/.claude/pipeline-templates/orchestrate.sh ./orchestrate.sh
   cp ~/.claude/pipeline-templates/verify-ui.mjs ./scripts/verify-ui.mjs
   cp ~/.claude/pipeline-templates/verify-existing-data.sh ./scripts/verify-existing-data.sh
   chmod +x orchestrate.sh scripts/verify-existing-data.sh
   ```

3. Add pipeline artifacts to .gitignore (if not already present):
   ```
   pipeline/evidence.md
   .claude/logs/
   .claude/screenshot*.png
   .claude/auth-state.json
   .claude/pipeline-prompts/
   .env.test
   ```

4. Detect the project's stack and create an appropriate test user setup script:
   - If package.json contains `@supabase/supabase-js`: create a Supabase-based test user script
   - If package.json contains `next-auth`: create a NextAuth-based test user script
   - Otherwise: create a generic template and tell the user to customize it

5. Create a project-specific `pipeline/README.md` explaining how to use the pipeline in this project.

6. Run `npx tsx scripts/setup-test-user.ts` if the script was created and the dev environment is configured.

7. Report what was created and any manual steps remaining (like setting DATABASE_URL).

## Important
- Do NOT overwrite existing files — check first and skip if they exist
- Do NOT modify the project's CLAUDE.md — that's project-specific content
- The global rules in ~/.claude/rules/ auto-load and don't need copying
