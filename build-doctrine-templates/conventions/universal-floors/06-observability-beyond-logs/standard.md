# Floor 6 — Observability beyond logs — Standard

## Default
Emit the four golden signals (latency p50/p95/p99, traffic rps, error rate, saturation) per service + endpoint. Distributed traces via OpenTelemetry, sampled at head=10% / tail=100%-on-error. Dashboards for service health + key user funnels. Alert only on user-impacting conditions; warn on internal SLO breaches.

## Alternatives
- **Prometheus + Grafana** — open source, self-hosted, mature. Choose for cost-sensitive ops with Prometheus expertise.
- **Datadog / New Relic / Honeycomb** — managed APM. Choose to outsource ops complexity; recurring cost.
- **Cloud-native (CloudWatch, Stackdriver)** — minimal setup, vendor lock-in, less powerful than dedicated APM.
- **OpenTelemetry-only** — vendor-neutral; can backend to anything. Slight setup overhead, but futureproof.

## When to deviate
- Edge / serverless environments may not support sidecars or agents — use lightweight library-based emission.
- Privacy-sensitive workloads (healthcare, financial PII) require careful trace-attribute scrubbing; never include user-identifiable fields in trace tags.

## Cross-references
- Floor 1 (logging) — logs are one signal; metrics + traces are the others.
- Floor 5 (auth) — security events surface here as a separate dashboard.
- Floor 2 (error handling) — error-rate metric derives from emitted error events.
