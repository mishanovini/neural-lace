# Rules for API route changes (src/app/api/**)

When modifying or creating an API route:

1. After writing the route, test it: `curl -s http://localhost:3000/api/<route> | jq '.'`
2. Document the FULL response shape in evidence — every field, every nested object
3. If the route requires auth, test with a valid session token
4. Check the route is included in auth middleware matcher (middleware.ts)
5. For Supabase queries: verify RLS policies allow the query for the expected user role
6. If referencing a new column, confirm it exists:
   `curl -s "$SUPABASE_URL/rest/v1/<table>?select=<column>&limit=1" -H "apikey: $ANON_KEY"`
