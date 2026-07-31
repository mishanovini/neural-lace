# O.4 doctor-predicate fragment

None. O.6 owns all doctor predicates per the dispatch map (§O.0.2: "Doctor
itself is orchestrator-only; O.6 output is ~all fragments"). O.4's own
`check_obs_cockpit_fresh` predicate (WARN if the cockpit server is
registered for autostart but its derived-cache stamp is >1h old while
sessions are live) is explicitly listed under §O.6 deliverables, not §O.4's.

Note for O.6 (informational, not a fragment this task ships): the cockpit's
own freshness signal is `GET /api/health`'s `oldest_pane_age_ms` field
(`workstreams-ui/server/server.js`) — the derived-cache stamp O.6's
predicate should read is the max of the six pane `derived_at` timestamps,
equivalently exposed there.
