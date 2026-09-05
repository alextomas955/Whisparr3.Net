#!/usr/bin/env python3
"""Assert that docs/SURFACE.md still says what spec/openapi.generated.json says.

Derives three things from the committed spec and set-compares each against the document: the
total operation count, the operations whose declared 2xx response carries no content, and the
operations that are generated but not useful from C#. Both sides of every comparison are
printed, so a passing run says what it checked rather than only that it passed.

Refuses in three cases, each of which is a way this gate could otherwise report success while
proving nothing.

    Either side of any comparison is empty. A document whose tables failed to parse yields an
    empty parsed set, and an empty set compared against an empty set differs in nothing.

    The derived total is not 272. A spec that lost operations shrinks both sides together, and
    the set comparison alone would still pass.

    The count the document states in prose does not equal the derived count. The table and the
    sentence beside it are two separate assertions, and a reader trusts the sentence.

This reads one committed document with a known shape and compares two sets of strings. It is
deliberately not an OpenAPI parser.

    python scripts/assert_surface.py
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "spec" / "openapi.generated.json"
DOCUMENT = ROOT / "docs" / "SURFACE.md"

EXPECTED_TOTAL = 272

HTTP_METHODS = ("get", "put", "post", "delete", "patch", "head", "options", "trace")

# The not-useful surface is derived from this path list rather than from a name heuristic. A
# heuristic over operation names silently changes meaning on a spec refresh; a path that
# disappears from the spec makes this list refuse instead.
NOT_USEFUL_PATHS = (
    "/{path}",
    "/content/{path}",
    "/login",
    "/logout",
    "/feed/v3/calendar/whisparr.ics",
)

# The two headings the tables sit under. Named here so a heading rename refuses rather than
# quietly parsing zero rows.
VOID_HEADING = "## The operations that return nothing"
NOT_USEFUL_HEADING = "## The operations that are generated but not useful"

# The sentence carrying the count in prose. Both numerals are checked against the derivation.
PROSE_COUNT = re.compile(r"(\d+) of the (\d+) operations")

ROW = re.compile(r"^\|\s*([A-Z]+)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*\|\s*$")


def die(*lines):
    """Print a refusal and exit 1. Nothing here writes, so there is nothing to undo."""
    for line in lines:
        print(line)
    sys.stdout.flush()
    sys.exit(1)


def derive():
    """The three sets the spec declares, as (method, path, operationId) triples."""
    with SPEC.open(encoding="utf-8") as handle:
        spec = json.load(handle)

    operations = set()

    for path, item in spec["paths"].items():
        for method, operation in item.items():
            if method not in HTTP_METHODS:
                continue
            operations.add((method.upper(), path, operation["operationId"]))

    content_less = set()
    not_useful = set()

    for path, item in spec["paths"].items():
        for method, operation in item.items():
            if method not in HTTP_METHODS:
                continue

            triple = (method.upper(), path, operation["operationId"])
            responses = operation.get("responses", {})
            successes = [r for code, r in responses.items() if code.startswith("2")]

            if not any("content" in response for response in successes):
                content_less.add(triple)

            if path in NOT_USEFUL_PATHS:
                not_useful.add(triple)

    return operations, content_less, not_useful


def parse_rows(text, heading):
    """The three-column rows under one heading, refusing when the heading is absent."""
    if heading not in text:
        die("%s carries no heading reading %r." % (DOCUMENT, heading))

    section = text.split(heading, 1)[1]
    section = re.split(r"^## ", section, maxsplit=1, flags=re.MULTILINE)[0]

    rows = set()

    for line in section.splitlines():
        match = ROW.match(line)
        if match is None:
            continue
        method, path, operation = match.groups()
        if method == "Method":
            continue
        rows.add((method, path, operation))

    return rows


def compare(label, derived, parsed):
    """Report both sides of one comparison and return how many ways it failed."""
    print("%s: derived %d, document %d" % (label, len(derived), len(parsed)))

    failures = 0

    if not derived:
        print("  the derived %s set is empty, so this comparison proves nothing" % label)
        failures += 1

    if not parsed:
        print("  the %s set parsed from the document is empty, so this comparison proves nothing" % label)
        failures += 1

    for triple in sorted(derived - parsed):
        print("  in the spec and absent from the document: %s %s %s" % triple)
        failures += 1

    for triple in sorted(parsed - derived):
        print("  in the document and absent from the spec: %s %s %s" % triple)
        failures += 1

    return failures


def main():
    if not SPEC.exists():
        die("%s does not exist. There is nothing to derive from." % SPEC)

    if not DOCUMENT.exists():
        die(
            "%s does not exist." % DOCUMENT,
            "An absent document parses as an empty set, and comparing an empty set against an"
            " empty set proves nothing. Refusing rather than passing.",
        )

    operations, content_less, not_useful = derive()

    text = DOCUMENT.read_text(encoding="utf-8")
    document_void = parse_rows(text, VOID_HEADING)
    document_not_useful = parse_rows(text, NOT_USEFUL_HEADING)

    stated = PROSE_COUNT.search(text)

    if stated is None:
        die("%s states no count in prose matching %r." % (DOCUMENT, PROSE_COUNT.pattern))

    stated_content_less = int(stated.group(1))
    stated_total = int(stated.group(2))

    failures = 0

    print("total operations: derived %d, document %d" % (len(operations), stated_total))
    if len(operations) != stated_total:
        print("  the document states a total the spec does not declare")
        failures += 1

    failures += compare("content-less operations", content_less, document_void)
    failures += compare("not-useful operations", not_useful, document_not_useful)

    if len(operations) != EXPECTED_TOTAL:
        print(
            "the spec declares %d operations and this gate expects %d. A spec that lost"
            " operations shrinks both sides of every comparison together, so the set"
            " comparisons above cannot catch it."
            % (len(operations), EXPECTED_TOTAL)
        )
        failures += 1

    if stated_content_less != len(content_less):
        print(
            "the document's prose states %d content-less operations and the spec declares %d."
            " The table and the sentence beside it are two separate assertions."
            % (stated_content_less, len(content_less))
        )
        failures += 1

    paths = {path for _, path, _ in not_useful}
    print("not-useful paths: %d" % len(paths))

    if failures:
        die("%d assertions failed." % failures)

    print("all assertions held.")


if __name__ == "__main__":
    main()
