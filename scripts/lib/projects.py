"""Where a project's files live, for the Python consumers.

    from lib.projects import discover
    for project in discover(vault):
        project["slug"], project["overview"], project["features"]

One reader for the layout, because there are now two consumers of it —
`build-vault-index.py` generates `projects/INDEX.md` and `project-for.py`
answers "what does the vault know about this repo" — and two implementations
of "what counts as a project" drift the same way two glob matchers do
(see lib/repo_match.py). The failure would be quiet and asymmetric: the index
listing a flat `projects/<name>.md` that the read path skips, so a committed
document is visible in Obsidian and invisible to every session.

This knows the shape and nothing else. Frontmatter, validation, sort order and
report wording stay with the caller — the index has problems to report and the
read path has a repo to filter by, and folding either into here would make this
the place both of them argue.

Two shapes are read:

    projects/<project>/_project.md            the stable overview
    projects/<project>/features/<feature>.md  one slice of work
    projects/<project>.md                     the flat shape, from before the split

The flat one stays supported because it is somebody's committed vault content;
an engine upgrade that stopped reading it would be this tool deciding to lose a
document.
"""

PROJECT_FILE = "_project.md"
FEATURES_DIR = "features"


def discover(vault):
    """Every project in the vault, slug-sorted, or [] when there is no projects/.

    Each entry is a dict:

        slug      the directory name, or the flat file's stem
        overview  Path to _project.md (or the flat file), None if a directory
                  holds features and no overview — a half-written project, which
                  is reported rather than skipped so its features stay visible
        features  Paths under features/, name-sorted; [] for a flat project
        flat      True for projects/<name>.md

    Stats the filesystem and reads nothing.
    """
    root = vault / "projects"
    if not root.is_dir():
        return []

    out = []
    for entry in sorted(root.iterdir()):
        if entry.is_dir():
            overview = entry / PROJECT_FILE
            out.append({
                "slug": entry.name,
                "overview": overview if overview.is_file() else None,
                "features": feature_files(entry),
                "flat": False,
            })
            continue
        if entry.suffix != ".md" or entry.name == "INDEX.md":
            continue
        out.append({
            "slug": entry.stem,
            "overview": entry,
            "features": [],
            "flat": True,
        })
    return out


def feature_files(project_dir):
    """The feature files under one project directory, name-sorted."""
    features = project_dir / FEATURES_DIR
    if not features.is_dir():
        return []
    return [p for p in sorted(features.glob("*.md")) if p.name != "INDEX.md"]
