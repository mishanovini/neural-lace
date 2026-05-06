# Floor 1 — Logging — Standard

## Default
Structured JSON logs, single line per event, captured by the runtime to stdout, aggregated externally. Levels: `debug`, `info`, `warn`, `error`, `fatal`. Required fields: `timestamp`, `level`, `service`, `request_id`, `message`. Never log: secrets, full PII. Retention: 30d hot, 1y cold.

## Alternatives
- **Plaintext / logfmt** — simpler, harder to query at scale. Choose when humans read logs more than machines do.
- **OpenTelemetry-native** — log/metric/trace unified emission. Choose when project commits to OTel for traces.
- **Library-direct streaming to aggregator** (Datadog, Splunk) — bypasses stdout. Choose only when runtime cannot capture stdout reliably.

## When to deviate
- Compliance regimes (HIPAA, PCI) may mandate specific log shapes / retention. Adopt verbatim.
- Embedded / IoT runtimes with no aggregator: rotating file with size limit; sample on overflow.
- Single-developer side projects: plaintext + tail acceptable through PMF.

## Cross-references
- Floor 6 (observability beyond logs) — metrics + traces + dashboards.
- Floor 3 (secrets) — never-log discipline starts here.
