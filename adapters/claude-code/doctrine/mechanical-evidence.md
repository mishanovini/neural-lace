# Mechanical Evidence — compact
> Enforcement: evidence.schema.json (locked shape), plan-edit-validator.sh (recognizes both formats), write-evidence.sh (deterministic capture). Full: doctrine/mechanical-evidence-full.md
> Applies: task-verification artifacts — structured artifacts replace prose narration.

- Default for structural / mechanical work: capture evidence via `write-evidence.sh capture --task <id> --plan <path> --check <spec> [--check <spec>...]`. It runs each check, auto-discovers files_modified from git, and writes a schema-valid artifact to `<plan-dir>/<plan-slug>-evidence/<task-id>.evidence.json`. Exit 0 on PASS, 1 on FAIL/INCOMPLETE.
- Check specs: `typecheck`, `lint`, `test:<name>`, `files-in-commit`, `schema-valid:<path>`, `exists:<path>`, `command:<cmd>`. Pick the ones that correspond to the task's actual claims — a hook task is typically `exists:<hook>.sh` + `command:<hook>.sh --self-test`.
- Six required schema fields: task_id, verdict (PASS|FAIL|INCOMPLETE), commit_sha, files_modified, mechanical_checks, timestamp. Optional escalation fields: runtime_evidence (replayable runtime entries the agent records after replaying them), prose_supplement, verifier, plan_path.
- Escalate to prose only for genuinely-novel judgment mechanical checks cannot express (e.g. "did the rewrite capture intent?"): populate `prose_supplement` on the JSON artifact (the mechanical fields are still required) or use the legacy `<plan>-evidence.md` prose block. When in doubt, default to mechanical.
- plan-edit-validator.sh accepts BOTH formats at checkbox-flip time: the structured `.evidence.json` (mtime-fresh, task_id match) or the legacy prose block. Closed plans with prose evidence stay valid — no migration.
- Don't hand-compose JSON evidence — the helper writes it schema-valid by construction. Your job is invocation + outcome interpretation, not narrative composition; the artifact records what the system showed, not what the builder claims it showed.
