#!/usr/bin/env python3
"""Render docs/SURFACE.md from the committed spec.

The document is almost entirely derived: counts of operations, and tables listing them. It used to
be typed by hand and guarded by a script that re-derived every number and required every sentence
stating a count to appear verbatim. That shape pinned this repository to one release of the API. A
Whisparr release that adds an operation moved a count, and the build went red as though something
had broken.

Generating them removes the pin. Nothing here asserts that the API has a particular number of
operations. The counts are whatever the committed spec declares, and they change when it changes.

Prose lives in generator/templates/SURFACE.md.in and is copied through untouched. Derived values are
substituted for @@TOKEN@@ markers. The marker syntax is deliberately not Python's own str.format
braces, because every path in these tables can contain a brace: /api/v3/movie/{id} is a real key.

Three things here are judgement rather than derivation, and each is a named list below. Which
paths serve the web interface, which responses carry credentials, and which operations have effects
the spec does not describe are all facts about Whisparr that no field of the spec states. They are
written down, and every one is checked against the spec on each run: a path that disappears
upstream fails the render rather than leaving prose describing an operation nobody can call.

The lists describe. They do not instruct. What a caller does with an operation is the caller's
decision, and this library has no standing to rule on it.

    python generator/render_docs.py            # write the document
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

# Paths that serve Whisparr's browser interface or a calendar subscriber. A path list rather than
# an operation list, so a new method on one of these paths is picked up.
WEB_INTERFACE_PATHS = (
    "/{path}",
    "/content/{path}",
    "/login",
    "/logout",
    "/feed/v3/calendar/whisparr.ics",
)

# Operations the template describes by name under "Operations whose effect the spec does not
# describe". Checked, never rendered: the descriptions are prose and belong in the template. Listed
# here so that one leaving the spec fails the render instead of leaving prose about a method that
# no longer exists.
DESCRIBED_BY_NAME = (
    ("POST", "/api/v3/command"),
    ("POST", "/api/v3/release"),
    ("DELETE", "/api/v3/moviefile/{id}"),
    ("DELETE", "/api/v3/moviefile/bulk"),
    ("PUT", "/api/v3/moviefile/{id}"),
    ("PUT", "/api/v3/moviefile/bulk"),
    ("PUT", "/api/v3/moviefile/editor"),
)

# Operations whose responses carry credentials. Which responses leak is a property of the schemas
# rather than of the method, so the rows are judgement and the render only checks that each
# operation still exists.
CREDENTIAL_ROWS = (
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
    web = [r for r in ops if r[1] in WEB_INTERFACE_PATHS]

    declared = {(r[0], r[1]) for r in ops}
    missing = sorted(set(WEB_INTERFACE_PATHS) - {r[1] for r in web})
    if missing:
        die("WEB_INTERFACE_PATHS names paths the spec no longer declares: %s" % missing,
            "Remove them from generator/render_docs.py, and the prose that describes them.")
    missing = [(m, p) for m, p, _ in CREDENTIAL_ROWS if (m, p) not in declared]
    if missing:
        die("CREDENTIAL_ROWS names operations the spec no longer declares: %s" % missing,
            "Those rows warn that a response carries a secret. Do not just delete them; check "
            "whether the credential moved to another operation.")
    missing = [(m, p) for m, p in DESCRIBED_BY_NAME if (m, p) not in declared]
    if missing:
        die("DESCRIBED_BY_NAME names operations the spec no longer declares: %s" % missing,
            "The template describes each one by name, so fix the list and the prose together.")

    credential_table = ["| Operation | What its response carries |", "| --- | --- |"]
    credential_table += ["| `%s %s` | %s |" % row for row in CREDENTIAL_ROWS]

    text = (TEMPLATES / "SURFACE.md.in").read_text(encoding="utf-8")
    for token, value in (
        ("@@RAW_TOTAL@@", str(len(raw_ops))),
        ("@@TOTAL@@", str(len(ops))),
        ("@@VOID_COUNT@@", str(len(void))),
        ("@@VOID_TABLE@@", table(in_document_order(void))),
        ("@@WEB_INTERFACE_TABLE@@", table(in_document_order(web))),
        ("@@CREDENTIAL_TABLE@@", "\n".join(credential_table)),
    ):
        text = text.replace(token, value)
    return text, len(void), len(web)


def main():
    parser = argparse.ArgumentParser(description="Render docs/SURFACE.md from the committed spec.")
    parser.add_argument("--check", action="store_true",
                        help="do not write; exit 1 if the document on disk differs")
    args = parser.parse_args()

    for path in (RAW_SPEC, SPEC):
        if not path.exists():
            die("%s does not exist. There is nothing to render from." % path)

    raw_ops = operations(json.load(RAW_SPEC.open(encoding="utf-8")))
    ops = operations(json.load(SPEC.open(encoding="utf-8")))

    surface, void_count, web_count = render_surface(raw_ops, ops)

    print("spec declares %d operations raw, %d generated" % (len(raw_ops), len(ops)))
    print("  SURFACE.md  %d return nothing, %d serve the web interface" % (void_count, web_count))

    stale = []
    for name, text in (("SURFACE.md", surface),):
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
            die("", "%s differs from the render." % ", ".join(stale),
                "Run: python generator/render_docs.py")
        print("the document matches the render.")


if __name__ == "__main__":
    main()
