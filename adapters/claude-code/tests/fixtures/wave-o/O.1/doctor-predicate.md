# O.1 doctor-predicate fragment

**None.** Per specs-o §O.1 deliverable 5 and §O.0.2's dispatch map, the
doctor (`harness-doctor.sh`) is owned by O.6, which implements
`check_obs_consumer_map` (contract C3's enforcing predicate: every
ledger-observed event type AND every literal event string passed to
`ledger_emit`/`ledger_emit_typed` in the repo has an entry with >=1
consumer in `observability-consumer-map.json`; unknown-in-map = RED
naming the type) along with `check_obs_writers_firing` and
`check_obs_heartbeats_fresh`.

O.1 ships the CONSUMER MAP itself (seeded correct on day one, per the
plan's own instruction: "name them now, that is the point of the map")
and the event-emitting call sites the predicate will later check against
— but writes no doctor code. O.6's builder should treat this task's
`observability-consumer-map.json` (18 event types, 8 pre-existing + 10
Wave-O new, every entry >=1 named consumer, JSON-schema-valid) as the
fixture input for `check_obs_consumer_map`'s own RED/GREEN self-test
scenarios.
