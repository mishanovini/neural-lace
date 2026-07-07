# O.5 doctor predicate fragment

**None from this task.** O.6 ("Pipeline health in doctor") owns all doctor
predicates for the observability pipeline per the §O.0.2 dispatch map, including
push-adjacent health if any is warranted (e.g. "sent.jsonl growing while known
push-worthy state exists" would be an O.6-shaped check, not an O.5 one). This task's
own correctness is proven by its `--self-test` (18 scenarios, `bash
adapters/claude-code/scripts/ntfy-push.sh --self-test`) plus the real-machine
livesmoke cited in this task's report-back — no doctor predicate is being withheld
here, there simply isn't a pipeline-health check this task is positioned to author
without duplicating O.6's remit.
