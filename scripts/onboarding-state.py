#!/usr/bin/env python3
"""Is this repo onboarded, and has the question already been answered?

One command, because `update-second-brain` runs inside the repo that was worked
on and had no way to ask. The answer lives in three places — the machine's repo
registry, a `.sbw-version` or provenance marker in the repo, and the never-ask
list next to the registry — and an agent reconstructing it from those three by
hand gets it right most of the time, which for a prompt shown at the end of
every session is not good enough.

Usage:
  onboarding-state.py [--repo PATH]              # the verdict for one repo
  onboarding-state.py --decline [--reason TEXT]  # answered never; stop asking
  onboarding-state.py --undecline                # put it back in scope
  onboarding-state.py --list                     # the never-ask list

Exit codes, which are the part a caller acts on:
  0  nothing to ask — onboarded, deliberately declined, or never a target
  1  not onboarded, and nothing on this machine says that was on purpose
  3  undetermined — no such directory; it does not guess

1 is a *question*, not a fault: `check-followups.py` exits 0 on a backlog for
the same reason, and this exits 1 because the only caller is a prompt and a
prompt needs a yes/no. Nothing here renders, and nothing here writes to a repo.

Read-only apart from --decline / --undecline, which write one line to this
machine's config directory. Stdlib only.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.onboarding import classify, decline, declined_entries  # noqa: E402
from lib.onboarding import declined_path, engine_root, undecline  # noqa: E402

# The state a caller should act on, and the code it exits with. Kept here rather
# than in lib/onboarding.py: the states are a classification, and which of them
# is worth interrupting somebody about is this command's opinion.
EXIT_FOR = {
    "onboarded": 0,
    "declined": 0,
    "skip": 0,
    "not-onboarded": 1,
    "undetermined": 3,
}


def render_command(repo):
    return f"{engine_root()}/scripts/render.py {repo}"


def offer(repo):
    """The three ways to say yes and the one way to say never, as printed lines.

    Printed under a `not-onboarded` verdict so the caller hands over commands
    rather than a description of them. `--local` is on the list at all because
    not every repo is yours to add conventions to, and the failure it prevents
    is silent: rendered files committed to somebody else's remote.
    """
    return [
        "",
        "  shared    " + render_command(repo),
        "  quiet     " + render_command(repo) + " --local",
        "            (rendered files stay out of that repo's remote,",
        "             via .git/info/exclude — per clone, never committed)",
        "  never     " + f"{engine_root()}/scripts/onboarding-state.py "
                         f"--repo {repo} --decline --reason 'why'",
        "",
        "  Not now is also an answer, and needs no command — the next wrap-up",
        "  in this repo asks again.",
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", help="repo to classify (default: the working directory)")
    ap.add_argument("--decline", action="store_true",
                    help="record that onboarding was offered and refused, so "
                         "nothing asks about this repo again")
    ap.add_argument("--undecline", action="store_true",
                    help="take this repo off the never-ask list")
    ap.add_argument("--reason", help="why, recorded with a --decline. Optional, "
                                     "and the half worth writing")
    ap.add_argument("--list", action="store_true", dest="list_declined",
                    help="print the never-ask list and exit")
    ap.add_argument("--count", action="store_true",
                    help="with --list, print how many repos are on it and "
                         "nothing else — for a caller that reports it in one line")
    ap.add_argument("--quiet", action="store_true",
                    help="print nothing; the exit code is the answer")
    args = ap.parse_args()

    if args.decline and args.undecline:
        ap.error("--decline and --undecline are opposites; pick one")
    if args.reason and not args.decline:
        ap.error("--reason records why a --decline was made; it needs one")

    if args.count and not args.list_declined:
        ap.error("--count reports the size of the --list; it needs one")

    if args.list_declined:
        entries = declined_entries()
        if args.count:
            print(len(entries))
            return 0
        if not entries:
            if not args.quiet:
                print(f"no repos on the never-ask list ({declined_path()})")
            return 0
        if not args.quiet:
            print(f"never-ask list — {declined_path()}")
            for repo, fields in entries:
                reason = fields.get("reason")
                print(f"  {repo}" + (f"   ({reason})" if reason else ""))
        return 0

    repo = Path(args.repo).expanduser() if args.repo else Path.cwd()
    warn = lambda m: print(f"warning: {m}", file=sys.stderr)  # noqa: E731

    if args.decline or args.undecline:
        # Classified first, so a decline about a path that is not there fails
        # loudly instead of writing a line nothing will ever match.
        state, detail = classify(repo)
        if state == "undetermined":
            print(f"undetermined: {detail}", file=sys.stderr)
            return 3
        if args.decline:
            decline(repo, args.reason, warn=warn)
            if not args.quiet:
                print(f"declined: {repo}")
                print(f"  recorded in {declined_path()} — nothing will ask again.")
                print("  --undecline puts it back in scope.")
            if state == "onboarded":
                print("note: this repo is already onboarded, so the decline "
                      "changes nothing until it is unrendered.", file=sys.stderr)
        else:
            undecline(repo, warn=warn)
            if not args.quiet:
                print(f"back in scope: {repo}")
        return 0

    state, detail = classify(repo)
    if args.quiet:
        return EXIT_FOR[state]

    stream = sys.stderr if state == "undetermined" else sys.stdout
    print(f"{state}: {repo}", file=stream)
    print(f"  {detail}", file=stream)
    if state == "not-onboarded":
        for line in offer(repo):
            print(line)
    return EXIT_FOR[state]


if __name__ == "__main__":
    sys.exit(main())
