# FM Single-Entry Template

Copy the block below into the project's `docs/failure-modes.md`, replace the next `FM-NNN`, and fill every required field. Populate the two optional fields whenever they add signal (they are the highest-leverage fields for a future investigation — omit only when genuinely empty).

```markdown
## FM-NNN — <short title naming the class, not the incident>

- **Symptom.** <What an operator/user observes, 1-2 sentences. Write it as a searchable phenotype: concrete error-string class, observable state, the tool that misbehaves. This is the primary grep target.>
- **Root cause.** <What in the system actually produced the symptom. Mechanism, not blame.>
- **Detection.** <Which hook / agent / test / review step is positioned to surface this class. If purely behavioral today, say so — the gap is the point.>
- **Prevention.** <What stops the class at the source. If partial or aspirational, say so honestly.>
- **Example.** <One sanitized concrete instance, generic terms. No credentials, codenames, customer-tied dates, or username paths.>
- **Discriminator.** <Optional. The single observation or command that tells THIS FM apart from look-alike FMs sharing the same surface symptom. Omit only if Symptom is already unambiguous.>
- **Recovery.** <Optional. The immediate human steps to get unstuck RIGHT NOW — distinct from Prevention (mechanism-facing). What the investigator does in the next five minutes. Omit only if there is no distinct recovery beyond applying Prevention.>
```

Notes:
- `FM-NNN` is ascending and never recycled. Renaming an entry keeps its ID.
- If the failure matches an existing entry's `Symptom`, do NOT add a new entry — extend that entry's `Example` list instead (one mechanism per class, not one per instance).
- Reference the new/extended entry from any related code/config/doc change in the same commit.
- Full field semantics: `docs/conventions/failure-mode-catalogs.md` (harness repo).
