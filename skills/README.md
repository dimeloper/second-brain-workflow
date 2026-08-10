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
| Third-party skills you adopt | A `skills.json` in your own private content repo, fetched to `vendor/external/` | The roster is a personal opinion; this repo is public and ships the mechanism only |

The third row is the newest and the easiest to get wrong. It is for skills that
are pure content — a `SKILL.md` and maybe some references — from a repo you do
not control. They are pinned to a sha, allowlisted per source, and never
committed here. See the README's *Bringing your own skills*.

The distinction between rows two and three is **who owns the install**. If the
project ships an installer, a plugin marketplace, or an update command of its
own, it belongs in row two: fetching it here would fight its own updater, and
anything that writes hook configuration or project files is doing more than a
symlink can express. Row three is for the ones where a symlink is the whole
install.

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
