#!/usr/bin/env python3
"""Assert that a packed Whisparr3.Net package carries what a consumer needs, before it ships.

Every required entry is asserted by size, never by name. A name in the archive's central directory
says nothing about the bytes behind it, so each entry carries a byte floor and an entry that is
absent, empty or below its floor is a refusal.

Each XML documentation entry is parsed and required to declare at least MIN_MEMBERS `member`
elements, which is the property a consumer relies on. A documentation file can sit above its byte
floor and still document nothing, and the byte floor cannot see that.

The nuspec is read for identity: `<id>` must be the package id this repository publishes, and
`<version>` must equal the one supplied on the command line when one is supplied. The file name is
chosen by the pack; the nuspec is what nuget.org indexes.

The nuspec repository url must name a host a stranger can resolve, rather than an SSH account
alias. That defect is invisible from Directory.Build.props, because it only appears in the produced
nuspec.

Refuses an archive that holds no entries and an archive that has no nuspec, so a truncated or empty
package cannot pass by having nothing left to check.

This is an assertion over a fixed list of path strings, one XML attribute and two nuspec elements.
It is deliberately not a package parser, and it does not import generator/_common.py: the generator
directory is the spec pipeline and this is a repository gate.

    python scripts/assert_package.py artifacts/Whisparr3.Net.0.1.0.nupkg \\
        artifacts/Whisparr3.Net.0.1.0.snupkg --expect-version 0.1.0
"""

import argparse
import sys
import xml.etree.ElementTree as ElementTree
import zipfile
from typing import NoReturn

# The url Directory.Build.props sets. The value is repeated here on purpose: a gate that reads its
# expectation out of the thing it checks asserts nothing.
REPOSITORY_URL = "https://github.com/alextomas955/Whisparr3.Net"
# The package id Directory.Build.props sets, repeated here for the same reason.
PACKAGE_ID = "Whisparr3.Net"
# A host carrying an SSH account-alias suffix does not resolve for anyone but the machine that
# defined the alias. This is the defect the shipped package once carried.
ALIAS_HOST_MARKER = "github.com-"

# Both target frameworks ship a documentation file beside their assembly. Shipping those files does
# not stand in for observing the comments in an editor, which stays a human check.
#
# Each floor is an order-of-magnitude sentinel against a stub, deliberately not an equality, so an
# ordinary change to the library does not trip it. Measured against the pack of 2026-09-05: each
# Whisparr3.Net.dll is 2,657,792 bytes, each Whisparr3.Net.xml is 3,473,380 bytes, the packed
# README.md is 4,673 bytes, and the two pdb entries are 638,780 and 638,960 bytes. Every floor
# therefore has more than an order of magnitude of headroom below what the pack produces, except
# the readme, which has three times its floor.
PACKAGE_ENTRIES = (
    ("lib/net8.0/Whisparr3.Net.dll", 100000),
    ("lib/net8.0/Whisparr3.Net.xml", 100000),
    ("lib/net10.0/Whisparr3.Net.dll", 100000),
    ("lib/net10.0/Whisparr3.Net.xml", 100000),
    ("README.md", 1500),
)
SYMBOL_ENTRIES = (
    ("lib/net8.0/Whisparr3.Net.pdb", 10000),
    ("lib/net10.0/Whisparr3.Net.pdb", 10000),
)

# The documentation entries the member assertion applies to, named one at a time. The rule is never
# written over the file extension: the nupkg carries a 590-byte [Content_Types].xml and the snupkg a
# 465-byte one, both well-formed and both declaring zero member elements, so an extension-keyed rule
# refuses the real package on its first run.
DOCUMENTATION_ENTRIES = (
    "lib/net8.0/Whisparr3.Net.xml",
    "lib/net10.0/Whisparr3.Net.xml",
)
# Each documentation file currently declares 9,408 members, so this floor has the same kind of
# headroom the byte floors do.
MIN_MEMBERS = 1000


def die(*lines) -> NoReturn:
    """Print a refusal and exit 1. Nothing here writes, so there is nothing to undo."""
    for line in lines:
        print(line)
    sys.stdout.flush()
    sys.exit(1)


def read_names(path):
    """Every entry in the archive, refusing one that is unreadable or holds nothing."""
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
    except (OSError, zipfile.BadZipFile) as error:
        die("%s could not be read as an archive: %s" % (path, error))

    if not names:
        die("%s holds 0 entries. An empty package cannot be asserted about." % path)

    return names


def read_nuspec(path):
    """The parsed nuspec at the archive root, refusing an archive that has none."""
    with zipfile.ZipFile(path) as archive:
        candidates = [n for n in archive.namelist() if n.endswith(".nuspec") and "/" not in n]

        if not candidates:
            die("%s carries no nuspec at its root." % path)

        return ElementTree.fromstring(archive.read(candidates[0])), candidates[0]


def count_members(archive, entry):
    """The number of member elements the entry declares, or a parser message when it will not parse."""
    try:
        root = ElementTree.fromstring(archive.read(entry))
    except ElementTree.ParseError as error:
        return None, str(error)

    return len(root.findall(".//member")), None


def check_entries(path, expected):
    """Report one line per expected entry and return how many failed."""
    failures = 0

    with zipfile.ZipFile(path) as archive:
        sizes = {info.filename: info.file_size for info in archive.infolist()}

        for entry, floor in expected:
            size = sizes.get(entry)

            if size is None:
                state = "ABSENT"
            elif size == 0:
                state = "PRESENT BUT EMPTY"
            elif size < floor:
                state = "%d bytes, below the %d byte floor" % (size, floor)
            else:
                state = "%d bytes" % size

            failed = size is None or size < floor

            if not failed and entry in DOCUMENTATION_ENTRIES:
                members, parse_error = count_members(archive, entry)
                if parse_error is not None:
                    state += ", will not parse as XML: %s" % parse_error
                    failed = True
                elif members < MIN_MEMBERS:
                    state += ", %d member elements, below the %d member floor" % (
                        members,
                        MIN_MEMBERS,
                    )
                    failed = True
                else:
                    state += ", %d member elements" % members

            print("  %-40s %s" % (entry, state))

            if failed:
                failures += 1

    if failures:
        print("%s failed %d of %d required entries." % (path, failures, len(expected)))

    return failures


def check_identity(root, nuspec_name, expect_version):
    """Report the nuspec id and version and return how many of the asserted claims failed."""
    identifier = root.find(".//{*}id")
    version = root.find(".//{*}version")
    identifier_text = identifier.text if identifier is not None else None
    version_text = version.text if version is not None else None
    failures = 0

    print(
        "  %-40s id=%s version=%s"
        % (nuspec_name + " identity", identifier_text, version_text)
    )

    if identifier_text != PACKAGE_ID:
        print("Expected the nuspec id to read %s." % PACKAGE_ID)
        failures += 1

    if expect_version is not None and version_text != expect_version:
        print("Expected the nuspec version to read %s." % expect_version)
        failures += 1

    return failures


def check_repository(root, nuspec_name):
    """Report the nuspec repository element and return how many of its two claims failed."""
    repository = root.find(".//{*}repository")

    if repository is None:
        print("  %-40s ABSENT" % (nuspec_name + " repository"))
        return 2

    kind = repository.get("type")
    url = repository.get("url", "")
    failures = 0

    print("  %-40s type=%s url=%s" % (nuspec_name, kind, url))

    if kind != "git" or url != REPOSITORY_URL:
        print("Expected the repository element to read type=git url=%s." % REPOSITORY_URL)
        failures += 1

    if ALIAS_HOST_MARKER in url:
        print("The repository url names an account-alias host, which does not resolve.")
        failures += 1

    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("nupkg", help="the packed .nupkg to assert over")
    parser.add_argument("snupkg", nargs="?", help="the matching .snupkg, when one was produced")
    # Optional deliberately. .github/workflows/build-and-test.yml packs on every push and calls this
    # script without a version, so requiring one would turn the continuous path red.
    parser.add_argument(
        "--expect-version",
        help="the version the nuspec must declare; the version assertion is skipped without it",
    )
    args = parser.parse_args()

    failures = 0
    checked = 0

    names = read_names(args.nupkg)
    print("%s, %d entries" % (args.nupkg, len(names)))
    failures += check_entries(args.nupkg, PACKAGE_ENTRIES)
    checked += len(PACKAGE_ENTRIES)

    root, nuspec_name = read_nuspec(args.nupkg)
    failures += check_identity(root, nuspec_name, args.expect_version)
    checked += 2 if args.expect_version is not None else 1
    failures += check_repository(root, nuspec_name)
    checked += 2

    if args.snupkg:
        symbol_names = read_names(args.snupkg)
        print("%s, %d entries" % (args.snupkg, len(symbol_names)))
        failures += check_entries(args.snupkg, SYMBOL_ENTRIES)
        checked += len(SYMBOL_ENTRIES)

    if failures:
        die("%d of %d assertions failed." % (failures, checked))

    print("%d assertions, all held." % checked)


if __name__ == "__main__":
    main()
