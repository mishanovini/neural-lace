---
paths: **/*.tsx,**/*.jsx
---

# React / Next.js Standards

- Semantic HTML: `button` not `div onClick`, `a` not `span onClick`
- Keyboard-navigable controls with ARIA labels on icon-only buttons
- Every async data fetch must handle loading, error, and empty states
- Use React error boundaries so one broken component doesn't white-screen the app
- Server Components by default in Next.js; minimize `"use client"`
