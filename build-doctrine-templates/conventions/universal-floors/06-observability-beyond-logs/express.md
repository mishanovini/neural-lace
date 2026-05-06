# Floor 6 — Observability beyond logs — Express

Default: **emit the four golden signals** (latency, traffic, errors, saturation) per service + endpoint, traces sampled at head=10% / tail=100%-on-error, dashboards for service health and key user funnels, alerts only on user-impacting conditions.

- Metrics system: language-idiomatic (Prometheus, OpenTelemetry, or platform native).
- Traces: OpenTelemetry preferred for cross-service propagation.
- Dashboards: one for service-health (latency / errors / traffic / saturation) per service.
- Alerts: page only on user-impacting; warn on internal SLO breaches; never alert on what nobody acts on.
