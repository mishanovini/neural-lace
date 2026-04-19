# Rules for UI component changes (src/components/** and src/app/**/page.tsx)

When modifying or creating a UI component:

1. For EVERY prop or data field rendered in JSX, trace it:
   - Where does the data come from? (API endpoint, server component, context, prop)
   - What is the exact field name in the API response?
   - Is it optional/nullable? What's the fallback?

2. For conditional rendering (if, &&, ternary):
   - What condition controls visibility?
   - Is at least one real record in the database satisfying the condition?
   - If it depends on user role, does the test user have that role?

3. For new interactive elements:
   - Confirm the click handler is wired AND the element is visible
   - If inside a conditional block, confirm the condition is met
   - Add data-testid for pipeline verification

4. For styling:
   - If color comes from data (category colors), confirm the data path delivers the value
   - If using dynamic Tailwind classes, confirm the variable has a valid value

5. Verify with: `node scripts/verify-ui.mjs http://localhost:3000/<page> '[data-testid="<id>"]'`
