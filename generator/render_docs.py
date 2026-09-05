#!/usr/bin/env python3
"""Render docs/SURFACE.md and docs/DO-NOT-CALL.md from the committed spec.

Both documents are almost entirely derived: counts of operations, and tables listing them. They
used to be typed by hand and guarded by a script that re-derived every number and required every
sentence stating a count to appear verbatim. That shape pinned this repository to one release of
the API. A Whisparr release that adds an operation moved a count, and the build went red as though
something had broken.

Generating them removes the pin. Nothing here asserts that the API has a particular number of
operations. The counts are whatever the committed spec declares, and they change when it changes.

Prose lives in generator/templates/*.md.in and is copied through untouched. Derived values are
substituted for @@TOKEN@@ markers. The marker syntax is deliberately not Python's own str.format
braces, because every path in these tables can contain a brace: /api/v3/movie/{id} is a real key.

Two things here are judgement rather than derivation, and both are named lists below. NOT_USEFUL
is the set of paths that exist only to serve Whisparr's web interface. NEVER_CALL is the set of
operations the prose singles out. Neither can be read off the spec, so both are written down, and
both are checked against the spec on every run: a path that disappears upstream fails the render
rather than leaving a document that quietly describes an operation nobody can call.

    python generator/render_docs.py            # write the documents
    python generator/render_docs.py --check    # exit 1 if what is on disk differs
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATES = ROOT / "generator" / "templates"
RAW_SPEC = ROOT / "spec" / "openapi.raw.json"
SPEC = ROOT / "spec" / "openapi.generated.json"

HTTP_METHODS = ("get", "put", "post", "delete", "patch", "head", "options", "trace")
# The methods that change state on the instance. HEAD is read-only and is not a GET, which is why
# this is an explicit list rather than "everything except GET".
MUTATING_METHODS = ("POST", "PUT", "DELETE", "PATCH")

# Generated because this library covers the whole spec, not because a C# caller wants them. A path
# list rather than an operation list, so a new method on one of these paths is picked up.
NOT_USEFUL_PATHS = (
    "/{path}",
    "/content/{path}",
    "/login",
    "/logout",
    "/feed/v3/calendar/whisparr.ics",
)

# The operations the prose in DO-NOT-CALL.md.in singles out by name. Checked, never rendered: the
# reasons are prose and belong in the template.
NEVER_CALL = (
    ("POST", "/api/v3/command"),
    ("POST", "/api/v3/release"),
    ("DELETE", "/api/v3/moviefile/{id}"),
    ("DELETE", "/api/v3/moviefile/bulk"),
)

# Read-only operations whose responses carry credentials. They change nothing, so they are not on
# the state-mutating list, and recording one still writes a secret into a log. Which responses leak
# is a property of the schemas rather than of the method, so the rows are judgement and the render
# only checks that each operation still exists.
READONLY_ROWS = (
    ("GET", "/api/v3/config/host",
     "The instance API key and the admin password, both in plaintext. `HostConfigResource` "
     "declares `apiKey`, `password`, `passwordConfirmation`, `proxyPassword` and "
     "`sslCertPassword`."),
    ("GET", "/api/v3/config/host/{id}", "The same resource, reached by id."),
    ("GET", "/api/v3/log",
     "Log records from the instance database. Log text can contain the key."),
    ("GET", "/api/v3/log/file/{filename}",
     "Raw log file text, with no schema at all in the spec."),
    ("GET", "/api/v3/log/file/update/{filename}", "The same, for the updater's log files."),
)


def die(*lines):
    for line in lines:
        print(line)
    sys.stdout.flush()
    sys.exit(1)


def operations(spec):
    """Every operation in one spec, as (METHOD, path, operationId) triples."""
    found = []
    for path, item in spec["paths"].items():
        for method, operation in item.items():
            if method in HTTP_METHODS:
                found.append((method.upper(), path, operation.get("operationId", ""), operation))
    return found


def in_document_order(triples):
    """Sorted by path, then by method, which is the order both documents state they use."""
    return sorted(triples, key=lambda row: (row[1], row[0]))


def table(rows):
    """A three-column Markdown table of (method, path, operation) rows."""
    out = ["| Method | Path | Operation |", "| --- | --- | --- |"]
    out += ["| %s | %s | %s |" % row[:3] for row in rows]
    return "\n".join(out)


def render_surface(raw_ops, ops):
    void = [r for r in ops if not any(
        "content" in response
        for code, response in r[3].get("responses", {}).items()
        if code.startswith("2")
    )]
    not_useful = [r for r in ops if r[1] in NOT_USEFUL_PATHS]

    missing = set(NOT_USEFUL_PATHS) - {r[1] for r in not_useful}
    if missing:
        die("NOT_USEFUL_PATHS names paths the spec no longer declares: %s" % sorted(missing),
            "Remove them from generator/render_docs.py, and check the prose that describes them.")

    text = (TEMPLATES / "SURFACE.md.in").read_text(encoding="utf-8")
    for token, value in (
        ("@@RAW_TOTAL@@", str(len(raw_ops))),
        ("@@TOTAL@@", str(len(ops))),
        ("@@VOID_COUNT@@", str(len(void))),
        ("@@VOID_TABLE@@", table(in_document_order(void))),
        ("@@NOT_USEFUL_TABLE@@", table(in_document_order(not_useful))),
    ):
        text = text.replace(token, value)
    return text, len(void), len(not_useful)


def render_do_not_call(ops):
    mutating = [r for r in ops if r[0] in MUTATING_METHODS]
    readonly = [r for r in ops if r[0] not in MUTATING_METHODS]

    declared = {(r[0], r[1]) for r in ops}
    missing = [(m, p) for m, p, _ in READONLY_ROWS if (m, p) not in declared]
    if missing:
        die("READONLY_ROWS names operations the spec no longer declares: %s" % missing,
            "Those rows warn about credentials in a response. Do not just delete them; check "
            "whether the credential moved to another operation.")
    missing = [(m, p) for m, p in NEVER_CALL if not any(r[0] == m and r[1] == p for r in ops)]
    if missing:
        die("NEVER_CALL names operations the spec no longer declares: %s" % missing,
            "The prose in the template describes each one by name, so fix both together.")

    sections = []
    for tag in sorted({t for r in mutating for t in (r[3].get("tags") or ["(untagged)"])}):
        rows = in_document_order([r for r in mutating if tag in (r[3].get("tags") or ["(untagged)"])])
        sections.append("### %s\n\n%s\n" % (tag, table(rows)))

    counts = {}
    for row in ops:
        counts[row[0]] = counts.get(row[0], 0) + 1
    order = sorted(counts, key=lambda m: (-counts[m], m))
    method_table = ["| Method | Operations |", "| --- | --- |"]
    method_table += ["| `%s` | %d |" % (m, counts[m]) for m in order]
    method_table.append("| Total | %d |" % len(ops))

    readonly_table = ["| Operation | What its response carries |", "| --- | --- |"]
    readonly_table += ["| `%s %s` | %s |" % row for row in READONLY_ROWS]

    text = (TEMPLATES / "DO-NOT-CALL.md.in").read_text(encoding="utf-8")
    for token, value in (
        ("@@TOTAL@@", str(len(ops))),
        ("@@MUTATING@@", str(len(mutating))),
        ("@@READONLY@@", str(len(readonly))),
        ("@@READONLY_TABLE@@", "\n".join(readonly_table)),
        ("@@MUTATING_SECTIONS@@", "\n".join(sections).rstrip("\n")),
        ("@@METHOD_TABLE@@", "\n".join(method_table)),
    ):
        text = text.replace(token, value)
    return text, len(mutating), len(readonly)


def main():
    parser = argparse.ArgumentParser(description="Render docs/SURFACE.md and docs/DO-NOT-CALL.md from the committed spec.")
    parser.add_argument("--check", action="store_true",
                        help="do not write; exit 1 if a document on disk differs from the render")
    args = parser.parse_args()

    for path in (RAW_SPEC, SPEC):
        if not path.exists():
            die("%s does not exist. There is nothing to render from." % path)

    raw_ops = operations(json.load(RAW_SPEC.open(encoding="utf-8")))
    ops = operations(json.load(SPEC.open(encoding="utf-8")))

    surface, void_count, not_useful_count = render_surface(raw_ops, ops)
    do_not_call, mutating, readonly = render_do_not_call(ops)

    print("spec declares %d operations raw, %d generated" % (len(raw_ops), len(ops)))
    print("  SURFACE.md      %d return nothing, %d not useful" % (void_count, not_useful_count))
    print("  DO-NOT-CALL.md  %d state-mutating, %d read-only" % (mutating, readonly))

    stale = []
    for name, text in (("SURFACE.md", surface), ("DO-NOT-CALL.md", do_not_call)):
        target = ROOT / "docs" / name
        current = target.read_text(encoding="utf-8") if target.exists() else None
        if args.check:
            if current != text:
                stale.append(name)
            continue
        if current == text:
            print("  %s unchanged" % name)
        else:
            target.write_text(text, encoding="utf-8", newline="\n")
            print("  %s written" % name)

    if args.check:
        if stale:
            die("", "%s differ from the render." % ", ".join(stale),
                "Run: python generator/render_docs.py")
        print("both documents match the render.")


if __name__ == "__main__":
    main()
