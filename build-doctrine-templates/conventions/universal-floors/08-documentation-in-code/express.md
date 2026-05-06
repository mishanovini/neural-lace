# Floor 8 — Documentation in code — Express

Default: **JSDoc/TSDoc/docstrings on exported public APIs**, README at repo root + per-package, ADRs for non-trivial decisions, inline comments for non-obvious WHY (not WHAT).

- Exported APIs: doc the parameters, return shape, error cases, side effects.
- README: one-paragraph what + 3-5 line quick start + links to deeper docs.
- ADRs: when an "either way works" choice is made; when external constraints drive a non-obvious decision.
- Inline comments: explain WHY, not WHAT. The code says what; the comment says why.
