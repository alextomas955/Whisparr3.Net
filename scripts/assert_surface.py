#!/usr/bin/env python3
"""Assert that docs/SURFACE.md still says what the two committed specs say.

Derives five things and compares each against the document: the operation count the raw spec
declares, the operation count the generated spec declares, the operations whose declared 2xx
response carries no content, the operations that are generated but not useful from C#, and the
set of paths those not-useful operations sit on. Both sides of every comparison are printed, so
a passing run says what it checked rather than only that it passed.

The document states its counts in prose as well as in tables, and a reader trusts the prose. So
every sentence that carries a count is rebuilt here from the derived values and required in the
document verbatim, rather than matched by its numerals alone. A sentence matched by its numerals
can be inverted to say the opposite of the truth while the numerals stay put.

Refuses in these cases, each of which is a way this gate could otherwise report success while
proving nothing.

    Either committed spec is absent, or the document is absent. An absent document parses as an
    empty table and an empty table differs from an empty table in nothing.

    Either side of any comparison is empty. A document whose tables failed to parse yields an
    empty parsed table.

    The derived totals are not 273 and 272. A spec that lost operations shrinks both sides of a
    comparison together, and the comparisons alone would still pass.

    A rebuilt sentence does not appear in the document.

    A table row is present but out of place. The document states that both tables are sorted by
    path and then by method, so the rows are compared in order and not as a set.

    A not-useful operation is not content-less. The document states that relation in prose and
    it is derivable, so it is derived rather than trusted.

This reads two committed specs and one committed document with a known shape. It is deliberately
not an OpenAPI parser.

    python scripts/assert_surface.py
"""

import json
import re
import sys
from pathlib import Path
from typing import NoReturn

ROOT = Path(__file__).resolve().parent.parent
RAW_SPEC = ROOT / "spec" / "openapi.raw.json"
SPEC = ROOT / "spec" / "openapi.generated.json"
DOCUMENT = ROOT / "docs" / "SURFACE.md"

# The raw spec is the captured document. The generated spec is what the library was generated
# from, after pre-processing deletes the malformed root path. Both counts are pinned, for the
# reason no comparison below can cover: a spec that lost operations shrinks the derived side
# and the document side together.
EXPECTED_RAW_TOTAL = 273
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

# The not-useful section spells its counts as words. Only the small numbers the document uses
# are here; a derived count outside this range refuses rather than skipping its sentence.
NUMBER_WORDS = {
    1: "one",
    2: "two",
    3: "three",
    4: "four",
    5: "five",
    6: "six",
    7: "seven",
    8: "eight",
    9: "nine",
    10: "ten",
    11: "eleven",
    12: "twelve",
}

ROW = re.compile(r"^\|\s*([A-Z]+)\s*\|\s*(\S+)\s*\|\s*(\S+)\s*\|\s*$")


def die(*lines) -> NoReturn:
    """Print a refusal and exit 1. Nothing here writes, so there is nothing to undo."""
    for line in lines:
        print(line)
    sys.stdout.flush()
    sys.exit(1)


def load(path):
    """The parsed JSON at one committed spec path, refusing when it is absent."""
    if not path.exists():
        die("%s does not exist. There is nothing to derive from." % path)

    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def count_operations(spec):
    """How many operations one spec declares, under the same method filter as the derivation."""
    return sum(
        1
        for _, item in spec["paths"].items()
        for method in item
        if method in HTTP_METHODS
    )


def derive():
    """The three sets the generated spec declares, as (method, path, operationId) triples."""
    spec = load(SPEC)

    operations = set()
    content_less = set()
    not_useful = set()

    for path, item in spec["paths"].items():
        for method, operation in item.items():
            if method not in HTTP_METHODS:
                continue

            triple = (method.upper(), path, operation["operationId"])
            operations.add(triple)

            responses = operation.get("responses", {})
            successes = [r for code, r in responses.items() if code.startswith("2")]

            if not any("content" in response for response in successes):
                content_less.add(triple)

            if path in NOT_USEFUL_PATHS:
                not_useful.add(triple)

    return operations, content_less, not_useful


def in_document_order(triples):
    """One set of triples in the order the document lists them: by path, then by method."""
    return sorted(triples, key=lambda triple: (triple[1], triple[0]))


def parse_rows(text, heading):
    """The three-column rows under one heading, in order, refusing when the heading is absent."""
    if heading not in text:
        die("%s carries no heading reading %r." % (DOCUMENT, heading))

    section = text.split(heading, 1)[1]
    section = re.split(r"^## ", section, maxsplit=1, flags=re.MULTILINE)[0]

    rows = []

    for line in section.splitlines():
        match = ROW.match(line)
        if match is None:
            continue
        method, path, operation = match.groups()
        if method == "Method":
            continue
        rows.append((method, path, operation))

    return rows


def compare(label, derived, parsed):
    """Report both sides of one comparison and return how many ways it failed.

    Membership and order are reported separately. A reordered table and a wrong row are
    different defects and a reader fixing one needs to know which one happened.
    """
    print("%s: derived %d, document %d" % (label, len(derived), len(parsed)))

    failures = 0

    if not derived:
        print("  the derived %s table is empty, so this comparison proves nothing" % label)
        failures += 1

    if not parsed:
        print(
            "  the %s table parsed from the document is empty, so this comparison proves"
            " nothing" % label
        )
        failures += 1

    derived_set = set(derived)
    parsed_set = set(parsed)

    for triple in sorted(derived_set - parsed_set):
        print("  in the spec and absent from the document: %s %s %s" % triple)
        failures += 1

    for triple in sorted(parsed_set - derived_set):
        print("  in the document and absent from the spec: %s %s %s" % triple)
        failures += 1

    if derived_set == parsed_set and list(derived) != list(parsed):
        for index, (want, got) in enumerate(zip(derived, parsed)):
            if want != got:
                print(
                    "  the %s rows carry the right operations in the wrong order. Row %d should"
                    " read %s %s %s and reads %s %s %s."
                    % ((label, index + 1) + want + got)
                )
                break
        failures += 1

    return failures


def number_word(value):
    """The English word for one small derived count, refusing outside the range in use."""
    if value not in NUMBER_WORDS:
        die(
            "the derivation produced %d, which this gate carries no word for. The document"
            " spells that count as a word, so the sentence cannot be rebuilt. Extend"
            " NUMBER_WORDS." % value
        )
    return NUMBER_WORDS[value]


def expected_sentences(raw_total, total, content_less, not_useful, not_useful_paths):
    """The sentences the document has to carry, rebuilt from the derived values."""
    return (
        ("the declared raw count", "The Whisparr 3 API declares %d operations" % raw_total),
        ("the generated count", "this library generates all %d that remain" % total),
        ("the void count", "%d of the %d operations return no value" % (content_less, total)),
        ("the repeated void count", "The reason is the same for all %d" % content_less),
        (
            "the single-category claim",
            "so the whole %d falls into that single category" % content_less,
        ),
        (
            "the not-useful counts",
            "%s operations across %s paths"
            % (number_word(not_useful).capitalize(), number_word(not_useful_paths)),
        ),
        (
            "the overlap claim",
            "All %s also appear in the table above, so all %s return nothing as well"
            % (number_word(not_useful), number_word(not_useful)),
        ),
    )


def assert_sentences(text, sentences):
    """Require each rebuilt sentence verbatim, printing every one with whether it was found."""
    # Whitespace is collapsed on both sides because the document wraps at 100 columns and
    # several of these sentences straddle a line break.
    flattened = " ".join(text.split())

    failures = 0

    for label, sentence in sentences:
        found = sentence in flattened
        print("  %-26s %s %r" % (label, "found " if found else "ABSENT", sentence))
        if not found:
            failures += 1

    return failures


def main():
    if not DOCUMENT.exists():
        die(
            "%s does not exist." % DOCUMENT,
            "An absent document parses as an empty table, and comparing an empty table against"
            " an empty table proves nothing. Refusing rather than passing.",
        )

    raw_total = count_operations(load(RAW_SPEC))
    operations, content_less, not_useful = derive()

    text = DOCUMENT.read_text(encoding="utf-8")
    document_void = parse_rows(text, VOID_HEADING)
    document_not_useful = parse_rows(text, NOT_USEFUL_HEADING)

    failures = 0

    print("raw operations: derived %d, expected %d" % (raw_total, EXPECTED_RAW_TOTAL))
    if raw_total != EXPECTED_RAW_TOTAL:
        print(
            "  the captured spec declares a total this gate does not expect. A spec that lost"
            " operations shrinks both sides of every comparison below together."
        )
        failures += 1

    print("generated operations: derived %d, expected %d" % (len(operations), EXPECTED_TOTAL))
    if len(operations) != EXPECTED_TOTAL:
        print(
            "  the generated spec declares a total this gate does not expect, for the same"
            " reason."
        )
        failures += 1

    failures += compare(
        "content-less operations", in_document_order(content_less), document_void
    )
    failures += compare(
        "not-useful operations", in_document_order(not_useful), document_not_useful
    )

    derived_paths = {path for _, path, _ in not_useful}
    print(
        "not-useful paths: derived %d, list %d"
        % (len(derived_paths), len(set(NOT_USEFUL_PATHS)))
    )
    if derived_paths != set(NOT_USEFUL_PATHS):
        print(
            "  a path is on one side of the comparison and not the other: %s"
            % sorted(derived_paths ^ set(NOT_USEFUL_PATHS))
        )
        failures += 1

    stray = not_useful - content_less
    print(
        "not-useful operations that are also content-less: %d of %d"
        % (len(not_useful) - len(stray), len(not_useful))
    )
    for triple in sorted(stray):
        print("  returns a value, so the document's overlap claim is wrong: %s %s %s" % triple)
        failures += 1

    print("sentences the document has to carry:")
    failures += assert_sentences(
        text,
        expected_sentences(
            raw_total, len(operations), len(content_less), len(not_useful), len(derived_paths)
        ),
    )

    if failures:
        die("%d assertions failed." % failures)

    print("all assertions held.")


if __name__ == "__main__":
    main()
