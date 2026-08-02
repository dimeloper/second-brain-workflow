---
name: mcp-per-project
description: >
  Set up or fix per-project MCP isolation in Cursor and Claude Code, so
  concurrent agent sessions for different products (e.g. Acme vs Globex vs
  Initech) each get their own Railway, Postgres, Logfire, PostHog, etc. Use when
  the user mentions MCP bleed across projects, global mcp.json pollution,
  multiple Railway accounts/tokens on one machine, wants project-scoped MCP
  servers, or when onboarding a product repo (invoked from the onboard-repo
  skill).
---

# Per-project MCP

Also run as **step 6 of `onboard-repo`** for every product backend or sibling
app — do not wait for the user to say "MCP".

## Problem

Both agents have a machine-wide MCP scope that every session loads. Putting
`railway` + `railway-acme` there means Globex sessions see Acme tools, and a
single `railway login` fights across accounts.

| | Machine-wide (keep empty of product infra) | Per-project (use this) |
|---|---|---|
| **Cursor** | `~/.cursor/mcp.json` | `<repo>/.cursor/mcp.json` |
| **Claude Code** | user scope, `~/.claude.json` | `<repo>/.mcp.json` (project scope) |

Claude Code also has a *local* scope — project-specific but private to you,
stored outside the repo. Use it for a server you need but shouldn't commit;
`.mcp.json` is the checked-in, team-shared one.

## Rules

1. **Machine-wide scope stays free of product infra.** Cursor: `mcpServers: {}`
   in `~/.cursor/mcp.json`. Claude Code: add nothing with `--scope user`.
   Exception: a genuinely universal, account-agnostic tool.
2. **Each product defines servers in its own repo** — `.cursor/mcp.json` for
   Cursor, `.mcp.json` for Claude Code. Commit `.mcp.json` and
   `.cursor/mcp.json.example`; gitignore `.cursor/mcp.json`.
3. **Name servers with a product suffix**: `railway-acme`, `railway-globex`,
   `railway-postgres-acme`, … Never a bare `railway` when several products share
   the machine. Note Claude Code reserves `workspace`, `claude-in-chrome`,
   `computer-use`, `Claude Preview`, `Claude Browser` — a server with a reserved
   name is skipped at load.
4. **Auth from that repo's `.env`**, not an interactive login:
   - `RAILWAY_TOKEN` — Railway project/environment token for that product only
   - `LOGFIRE_READ_TOKEN` — Logfire **read** token (`project:read`), not the write token
   - `POSTHOG_PERSONAL_API_KEY` — PostHog personal API key (MCP preset)

   Wrappers read `.env` and `exec` the server, so **one wrapper serves both
   agents**. New repos: put them in `.mcp/bin/`, which is agent-neutral.
   Existing repos already using `.cursor/bin/` can stay — it is only a path in
   config, so do not churn working setups.
5. **An always-on rule lists the exact server names** and forbids falling back
   to another product's MCP. This is a rule like any other: author it once and
   let `render.py` emit `.cursor/rules/mcp.mdc` and `.claude/rules/mcp.md`.
6. **Sibling apps** (frontend/mobile/Flutter) point absolute paths at the
   **backend's** wrappers, so a multi-root workspace has one secret source.
7. **Expo / React Native apps** also wire the Expo remote MCP under a suffixed
   name. Auth is OAuth — Cursor Settings → MCP, or `/mcp` in Claude Code (EAS
   paid plan). Keep it project-scoped. Skip on pure web/backend repos.

## Config shapes

Cursor, `<repo>/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "railway-acme": { "command": "${workspaceFolder}/.mcp/bin/railway-mcp.sh" }
  }
}
```

Claude Code, `<repo>/.mcp.json`:

```json
{
  "mcpServers": {
    "railway-acme": {
      "command": "${CLAUDE_PROJECT_DIR:-.}/.mcp/bin/railway-mcp.sh"
    },
    "expo-acme": {
      "type": "http",
      "url": "https://mcp.expo.dev/mcp"
    }
  }
}
```

Three things that bite:

- An entry with `url` but **no `type`** is a configuration error — Claude Code
  reads it as a stdio server and skips it. Always set `"type": "http"` (or
  `sse` / `ws`) alongside a `url`.
- `${VAR}` and `${VAR:-default}` expand in `command`, `args` and `env` only.
  `${CLAUDE_PROJECT_DIR}` needs the `:-.` default in a project-scoped file.
- Project-scoped servers require approval on first use. `claude mcp list` shows
  `⏸ Pending approval`; run `claude` interactively to approve, or
  `claude mcp reset-project-choices` to start over. A freshly cloned repo cannot
  approve its own servers until you accept the workspace trust dialog.

## Bootstrap a new product

```bash
# In <product>-backend — copy the wiring of the closest already-set-up backend.
# Find candidates:  ls -d ~/*/*/.mcp/bin ~/*/*/.cursor/bin 2>/dev/null
# Match on provider mix, not project name. Two common shapes:
#   full product  — Railway + Postgres + Logfire EU + PostHog
#   infra-light   — Railway prod + staging only
mkdir -p .mcp/bin
# Adapt the wrappers for this product's suffix, then write the config(s) the
# agents on this machine actually use:
#   Cursor       -> .cursor/mcp.json  (+ .cursor/mcp.json.example, gitignore the real one)
#   Claude Code  -> .mcp.json         (committed)
# Append empty RAILWAY_TOKEN / LOGFIRE_READ_TOKEN / POSTHOG_PERSONAL_API_KEY to .env
# Sibling apps: absolute paths -> the backend's wrappers, no local tokens
```

Wrapper shape, unchanged across agents:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
set -a; . ./.env; set +a
exec railway mcp
```

Reload after editing config or tokens: Cursor Settings → MCP → refresh, or
`/mcp` in Claude Code. If tokens are set, smoke-check with a cheap live call
(`whoami`, `SELECT 1`, Logfire schema, PostHog org list) and report ready vs
unauthorized. If tokens are empty, say what to create — do not block onboarding.

## Verify isolation

In an Acme session the available servers include `*-acme` and **not**
`*-globex`, and the reverse in a Globex session. Machine-wide scope lists no
product servers: `claude mcp list` for Claude Code, the global MCP list in
Cursor Settings.

## Do not

- Put product Railway / Postgres / Logfire / PostHog servers in `~/.cursor/mcp.json`
  or in Claude Code's user scope
- Use a bare server name like `railway` when several products share the machine
- Share one `RAILWAY_TOKEN` across products
- Fall back to another product's MCP when the right one is unauthorized
- Commit a config containing real tokens — tokens live in `.env`, referenced by
  the wrapper

## Related

- `onboard-repo` — invokes this as step 6
- Practice note `mcp-per-project` in the vault
