# Floor 5 — Auth and authorization — Express

Default: **identity from a verified token** (JWT or session cookie) issued by an auth provider; **authorization checked at the route boundary** with explicit role/permission lookup; audit-log every auth event.

- Identity source: external IdP (Auth0, Clerk, AWS Cognito) or session-backed app auth.
- Where authz checked: route handler, NOT in business logic.
- Audit-log: login, logout, permission denied, password change, MFA enroll/disable, role grant/revoke.
- Never: roll your own crypto.
