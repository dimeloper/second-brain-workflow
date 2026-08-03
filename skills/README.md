# Local skills

Source of truth for the skills this repo owns. Both Cursor and Claude Code
discover skills as a **flat** list in their own directory; the categories here
are for humans and for sync.

## What belongs here

Only skills that encode *our* conventions — the standards system, the vault,
onboarding, MCP isolation. Two kinds of skill deliberately do not live here:

| Kind | Where it lives instead | Why |
|------|------------------------|-----|
| Upstream skills we track | `vendor/obsidian-skills/` (pinned submodule) | Updates come from `git submodule update`; installed by allowlist |
| Vendor-published skills | The vendor's own installer | Carrying a copy means silently shipping a stale fork |

`use-railway` was vendored here until 2026-08-01 and is now Railway's own
install. A local copy meant a security fix had to be re-applied by hand, and the
copy could drift from the version Railway supports.

## Categories

| Folder | Purpose | Skills |
|--------|---------|--------|
| `workflow/` | Standards system, vault, onboarding, MCP isolation | `onboard-repo`, `obsidian-knowledge-base`, `update-second-brain`, `check-follow-ups`, `mcp-per-project` |

Add a category only when a clear domain appears. Prefer extending `workflow/`.

## Layout

```
skills/
  <category>/
    <skill-name>/
      SKILL.md          # required
      references/       # optional
      scripts/          # optional
```

`<skill-name>` must match the skill `name` in frontmatter and becomes the
directory name in each install directory after sync.

## Install / sync

```bash
./scripts/sync-skills.sh          # or: make sync-skills
```

Symlinks each skill into every directory in `SKILLS_DIRS` (default
`~/.cursor/skills` and `~/.claude/skills`), so edits here apply immediately in
both agents. The sync never touches a real directory or a symlink owned by
another tool — that is what keeps a vendor's own install safe.

Do **not** put product secrets in skills. Do **not** copy Cursor's built-in
skills from `~/.cursor/skills-cursor/` into this tree — those are managed by
the app.
