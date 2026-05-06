# Floor 1 — Logging — Express

Default: **structured JSON logs**, single line per event, captured by the runtime to stdout, aggregated by the platform.

- Levels: `debug`, `info`, `warn`, `error`, `fatal`.
- Required fields: `timestamp`, `level`, `service`, `request_id`, `message`.
- Never log: passwords, tokens, full credit card numbers, full SSNs, PHI.
- Retention: 30 days hot, 1 year cold (or per regulation, whichever is longer).
- Library: language-idiomatic structured logger.

If a project does not address logging at all, this is what is silently applied.
