# O.3 doctor-predicate fragment

None owned by this task (O.6 owns all doctor predicates per the dispatch
map). Opportunity note for O.6's own integration (not built here, no
action required unless O.6's builder wants it): `check_obs_heartbeats_fresh`
and `check_obs_scheduled_tasks` could source
`hooks/lib/observability-derive.sh` and call `od_sessions`/`hb_classify`
rather than re-implementing staleness math a third time — same
CANONICAL-COUNTERS-01 discipline this task's own doctrine file documents.
Left as a note, not a demand: O.6 was dispatched in parallel with O.3 and
may already have written its own predicates against the frozen C4 contract
by the time this fragment is read.
