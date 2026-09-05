#!/usr/bin/env python3
"""Assert that no tracked file cites a planning identifier a reader cannot resolve.

The planning tree is listed in `.gitignore`, so a tracker identifier written into a comment
resolves to nothing from the reader's side. It names a document that is not in the clone. The
repository's own instructions forbid those references in comments and documentation, and this
gate is what keeps the rule from depending on whoever reviews the next commit.

Scans the tracked file list rather than the working tree. `git ls-files` is the input, so
untracked build output can neither turn this red nor hide a hit, and the ignored planning tree
is out of scope by construction. Files that do not decode as UTF-8 text are skipped: the
committed specs and any binary asset carry no comments to check.

Reports every match as path, line number and the line's text, and exits 1 when there is one. A
clean run prints how many files it read, so a passing run says it looked at something rather
than only that it passed.

    python scripts/assert_no_planning_refs.py
"""

import re
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parent.parent

# `CLAUDE.md` is the repository's own contract file. It has to say where planning for this repo
# lives, so the identifiers in it are the content rather than a leak, and it ships to nobody.
# This is the whole exclusion list and it stays at one entry. An exclusion list is how a gate
# like this one stops seeing things.
#
# Compared by exact string equality against the `git ls-files` entry, which is a
# repository-relative path with forward slashes, so the root file is the literal `CLAUDE.md`.
# A suffix or basename test would silently excuse a future `docs/CLAUDE.md` as well, and it
# would do so without printing anything.
EXCLUDED_PATHS = frozenset({"CLAUDE.md"})

# Four alternatives: a tracker identifier, a bare decision identifier, the planning word for a
# release grouping, and the planning word for a stage followed by its number.
#
# Two refinements are load bearing and each was found by running this pattern, not by reading
# it. Widening either one starts firing on correct content:
#
#   The digit run is bounded at two and must not be followed by another digit or a dot. That is
#   what keeps `SHA-256` out of the results; `docs/REGENERATION.md` states two of those and they
#   are provenance a reader needs.
#
#   The prefix group holds the standards prefixes that share the identifier shape and are
#   legitimate content. That is what keeps `GPL-3.0` out; it appears in both committed spec
#   documents, which are generator output and cannot be edited, so without the exclusion this
#   gate is red on its first run and gets deleted rather than obeyed.
#
# The two identifier alternatives are upper case only, and the flag is scoped to the two word
# alternatives rather than applied to the whole pattern. Applied globally it also matches
# `probe-studio-1` in `test/Whisparr3.Net.UnitTests/ResponseTests.cs`, which is fixture data.
#
# The two planning words are written with a bracketed letter so this file does not match its own
# pattern. That keeps the exclusion list above at one entry instead of two.
PATTERN = re.compile(
    r"\b(?!(?:SHA|GPL|MIT|UTF|ISO|RFC|BSD|LGPL)-)[A-Z]{2,6}-F?\d{1,2}(?![\d.])"
    r"|\bD-\d{2}(?![\d.])"
    r"|(?i:\bm[i]lestone\b)"
    r"|(?i:\bp[h]ase[ -]?\d)"
)


def die(*lines) -> NoReturn:
    """Print a refusal and exit 1. Nothing here writes, so there is nothing to undo."""
    for line in lines:
        print(line)
    sys.stdout.flush()
    sys.exit(1)


def tracked_files() -> list[str]:
    """Return the tracked file list, or refuse if git cannot produce one."""
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        die(
            "git ls-files failed, so there is no file list to scan:",
            (result.stderr or "").strip(),
        )
    return [entry for entry in result.stdout.split("\0") if entry]


def main() -> None:
    paths = tracked_files()
    if not paths:
        die("git ls-files returned no files, so this run would pass over nothing.")

    scanned = 0
    hits = 0
    for path in paths:
        if path in EXCLUDED_PATHS:
            continue
        try:
            text = (ROOT / path).read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        scanned += 1
        for number, line in enumerate(text.splitlines(), start=1):
            if PATTERN.search(line):
                print("%s:%d: %s" % (path, number, line.strip()))
                hits += 1

    if hits:
        die(
            "",
            "%d planning reference(s) across the tracked tree, in %d files read."
            % (hits, scanned),
            "None of them resolves for a reader, because the planning tree is not committed.",
            "State the fact the comment was carrying instead of the identifier.",
        )

    print("%d tracked files read, no planning reference found." % scanned)


if __name__ == "__main__":
    main()
