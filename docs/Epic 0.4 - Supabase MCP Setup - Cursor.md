### Epic 0.4 - Supabase MCP Setup (Cursor on macOS)

This guide walks through integrating the official Supabase MCP Server with Cursor so you can run Supabase tasks (schema design, migrations, SQL, branches, logs, config) directly from your IDE.

Reference: Supabase announcement — [Supabase MCP Server](https://supabase.com/blog/mcp-server)

---

### 1) Prerequisites
- Node.js 18+ and npm
- Cursor (latest)
- Supabase account and access to your project
- A Supabase Personal Access Token (PAT)

---

### 2) Create a Supabase Personal Access Token (PAT)
1. Open Supabase Dashboard → Account → Access Tokens
2. Click “Generate new token”
3. Name it (e.g., "DailyManna MCP")
4. Scope: start with full access for development or restrict to the minimum needed; rotate regularly
5. Copy the token securely (don’t commit it)

Security notes:
- Never commit PATs. Prefer environment managers or Cursor secret storage if available.
- Rotate tokens on compromise or teammate changes.

---

### 3) Configure Cursor MCP
Create or update `.cursor/mcp.json` in your repository root:

```json
{
  "mcpServers": {
    "supabase": {
      "command": "npx",
      "args": [
        "-y",
        "@supabase/mcp-server-supabase@latest",
        "--access-token",
        "<personal-access-token>"
      ]
    }
  }
}
```

Tips:
- Replace `<personal-access-token>` with your PAT.
- Some environments require Windows-style invocation: `cmd /c npx ...`.
- If your client expects a slightly different JSON shape, consult Supabase MCP docs.

.gitignore reminder:
- Ensure `.cursor/mcp.json` is either scrubbed of secrets or excluded. Alternatively, reference an env var if/when supported by the client.

---

### 4) Verify the integration (smoke tests)
After saving `.cursor/mcp.json`, restart Cursor. Then from the AI chat, run a couple of basic tool calls:

- List tables:
  - Prompt: "Use the Supabase MCP tool to list database tables in the current project."
- Execute SQL (read-only):
  - Prompt: "Run a SQL query: select table_name from information_schema.tables where table_schema = 'public' order by 1;"

Expected: You should see a structured result containing your tables. If the call fails:
- Re-check the PAT, network, and project default context
- Inspect any error logs the tool returns

---

### 5) Common MCP Activities (Recipes)
These are typical actions we’ll perform during Daily Manna development. Always prefer working in a dev branch.

- Design tables and track with migrations
  - Action: Create a database branch; use tools to `create table` / `alter table` in the branch
  - Then capture the resulting SQL in our `docs/*.sql` migration files

- Execute SQL for checks and reports
  - Action: Run read-only queries to validate data, constraints, indexes, RLS behavior

- Create and manage database branches
  - Action: Create a new branch, apply migrations, validate changes, and merge when ready

- Fetch project configuration
  - Action: Retrieve project URL and anonymous key when needed for local setup

- Retrieve logs for debugging
  - Action: Pull recent logs (auth, realtime, db) to troubleshoot issues

- Generate TypeScript types (for web tooling or docs)
  - Action: Use the types generation tool when applicable; store outputs where appropriate

---

### 6) Safety & Best Practices
- Prefer a development database branch for schema or data changes
- Avoid destructive operations on production
- Confirm operations that drop/alter live structures
- Keep an easy rollback plan (reset branch to prior state)
- Rotate PATs and manage least privilege where feasible

---

### 7) Troubleshooting
- Tools not discovered?
  - Ensure `.cursor/mcp.json` is valid JSON and in repo root
  - Restart Cursor after changes
- Auth errors?
  - Verify your PAT is valid, not expired, and copied correctly
- SQL errors?
  - Validate schema names (`public`), permissions, and RLS policies

---

### 8) How We’ll Use MCP in Daily Manna
- Labels & Filtering (Epic 2.1):
  - Validate `labels` and `task_labels` schema, RLS, triggers, and indexes with quick SQL checks
  - Iterate schema in a branch and export migration SQL into `docs/Epic 2.1 - Labels & Filtering Migration.sql`
- Sync & Realtime: Quickly inspect triggers and publications
- Diagnostics: Fetch logs during sync or auth debugging sessions

---

### 9) Appendix
- Example read-only query:
```sql
select table_name
from information_schema.tables
where table_schema = 'public'
order by 1;
```

- Reminder: Do not commit secrets. If needed, maintain a local-only `.cursor/mcp.json` with your PAT.
