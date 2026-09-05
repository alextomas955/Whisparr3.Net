#!/usr/bin/env python3
"""Assert that a packed Whisparr3.Net package carries what a consumer needs, before it ships.

Refuses a package that is missing an XML documentation file beside either lib assembly, that
carries no readme for the listing page, or whose nuspec repository url names an account-alias host
rather than one a stranger can resolve. The alias defect is invisible from Directory.Build.props,
because it only appears in the produced nuspec.

Refuses an archive that holds no entries and an archive that has no nuspec, so a truncated or empty
package cannot pass by having nothing left to check.

This is an assertion over a fixed list of path strings and one XML attribute. It is deliberately
not a package parser, and it does not import generator/_common.py: the generator directory is the
spec pipeline and this is a repository gate.

    python scripts/assert_package.py artifacts/Whisparr3.Net.0.1.0.nupkg \\
        artifacts/Whisparr3.Net.0.1.0.snupkg
"""

import argparse
import sys
import xml.etree.ElementTree as ElementTree
import zipfile

# The url Directory.Build.props sets. The value is repeated here on purpose: a gate that reads its
# expectation out of the thing it checks asserts nothing.
REPOSITORY_URL = "https://github.com/alextomas955/Whisparr3.Net"
# A host carrying an SSH account-alias suffix does not resolve for anyone but the machine that
# defined the alias. This is the WR-11 residual the shipped package once carried.
ALIAS_HOST_MARKER = "github.com-"

# Both target frameworks ship a documentation file beside their assembly. That pair is the
# automatable half of DOCS-04, and it does not stand in for observing the comments in an IDE.
PACKAGE_ENTRIES = (
    "lib/net8.0/Whisparr3.Net.dll",
    "lib/net8.0/Whisparr3.Net.xml",
    "lib/net10.0/Whisparr3.Net.dll",
    "lib/net10.0/Whisparr3.Net.xml",
    "README.md",
)
SYMBOL_ENTRIES = (
    "lib/net8.0/Whisparr3.Net.pdb",
    "lib/net10.0/Whisparr3.Net.pdb",
)


def die(*lines):
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


def check_entries(path, names, expected):
    """Report one line per expected entry and return how many were absent."""
    missing = 0

    for entry in expected:
        present = entry in names
        print("  %-40s %s" % (entry, "present" if present else "ABSENT"))
        if not present:
            missing += 1

    if missing:
        print("%s is missing %d of %d required entries." % (path, missing, len(expected)))

    return missing


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
    args = parser.parse_args()

    failures = 0
    checked = 0

    names = read_names(args.nupkg)
    print("%s, %d entries" % (args.nupkg, len(names)))
    failures += check_entries(args.nupkg, names, PACKAGE_ENTRIES)
    checked += len(PACKAGE_ENTRIES)

    root, nuspec_name = read_nuspec(args.nupkg)
    failures += check_repository(root, nuspec_name)
    checked += 2

    if args.snupkg:
        symbol_names = read_names(args.snupkg)
        print("%s, %d entries" % (args.snupkg, len(symbol_names)))
        failures += check_entries(args.snupkg, symbol_names, SYMBOL_ENTRIES)
        checked += len(SYMBOL_ENTRIES)

    if failures:
        die("%d of %d assertions failed." % (failures, checked))

    print("%d assertions, all held." % checked)


if __name__ == "__main__":
    main()
