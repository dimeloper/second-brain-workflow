"""Markdown that will not render as written.

    from lib.markdown import wrapped_code_spans
    for lineno, line in wrapped_code_spans(text):
        ...

One rule, deliberately, and it is the one with evidence behind it: a code span
that wraps across a line break renders with its continuation indent intact.

CommonMark converts the line ending inside a code span to a space, then strips
**at most one** leading space. So this:

    - **Prod and staging deploy on different triggers.** `eks-deploy-staging.yml`
      has had one throughout (`group:
      staging-<release>-<ns>`, `cancel-in-progress: false`).

renders the span as `group:   staging-<release>-<ns>` — the newline became one
space and the two-space continuation indent survived, giving three. In a
document whose whole job is to be trusted as a record, a config key that renders
wrong is a config key somebody copies wrong.

Six instances were in the vault on 2026-08-31, five of them written that day,
and every check the engine runs was green: frontmatter validated, required
sections validated, the index regenerated clean. Nothing looked at the text.

There is a second symptom, and it is what makes this more than cosmetic. While
the span is wrapped, the `<release>` and `<ns>` on the continuation line sit
outside any *single-line* code span, so any tool reasoning line-by-line reads
them as raw HTML tags. One defect, two different wrong answers depending on who
is asking.

**Not a markdown linter, and not on the way to becoming one.** The notes are
hand-written prose with deliberate hard wrapping, and most of what a general
linter flags — line length, list markers, heading spacing — is house style it
would be wrong about. A second rule goes in when it has six real instances of
its own, the way this one did.

Stdlib only. Reads text, writes nothing.
"""

FENCE_CHARS = ("```", "~~~")


def wrapped_code_spans(text):
    """[(lineno, line)] for lines whose backtick count leaves a span open.

    A line with an odd number of backticks, outside a fenced block, opens a span
    that the next line has to close — which is the defect. Line numbers are
    1-based, to match every other report in this engine.

    Whole-file, never diff-scoped: a wrapped span's two halves are one fact, and
    a diff can show either half alone. A check reading only the changed hunk
    either false-positives on a legitimate edit to one line of the pair, or
    misses the defect entirely when the other half is the one that moved.
    """
    out = []
    in_fence = False
    fence = None
    for lineno, line in enumerate(text.splitlines(), 1):
        stripped = line.lstrip()
        if in_fence:
            # Only the same fence character closes it, so a ``` inside a ~~~
            # block stays content — which is how a note documenting markdown
            # writes about fences without ending its own.
            if stripped.startswith(fence):
                in_fence, fence = False, None
            continue
        opener = next((f for f in FENCE_CHARS if stripped.startswith(f)), None)
        if opener:
            in_fence, fence = True, opener
            continue
        # Inside a fence an odd backtick is content, which is why the two cases
        # above return before this one.
        if line.count("`") % 2 == 1:
            out.append((lineno, line))
    return out
