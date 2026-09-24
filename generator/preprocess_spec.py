#!/usr/bin/env python3
"""Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

One transform is left: the root security requirement is narrowed to the header scheme. Everything
else this script used to do is now correct in the document Whisparr serves.

    python generator/preprocess_spec.py
"""

import argparse
import json
import os
import re

from _common import die, resolve_repo_path, sha256_file, write_json_lf

# Mandatory auth, header scheme only.
#
# Whisparr declares both of its schemes at the root, which is the OpenAPI spelling for "either
# one". generichost does not read it that way: it emits a call to every declared scheme, so the
# document as served puts the key in the query string of every request, where it reaches access
# logs, proxy logs and Referer headers (upstream openapi-generator issue 24138). Narrowing the list
# to the header scheme is what keeps the key in a header.
#
# Not optional, either: Whisparr's Startup.cs pins the fallback policy to the API-key scheme and
# consults neither AuthenticationMethod nor AuthenticationRequired. The four operations that really
# are anonymous carry their own empty security list in the document and are left alone here.
SECURITY = [{"X-Api-Key": []}]

HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
# A valid C# identifier of the shape this library's public method names take. Anchored on purpose,
# and case-insensitive at the head because Whisparr writes its ids camelCase and the generator
# capitalises them.
OPERATION_ID_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9]*")


def main():
    parser = argparse.ArgumentParser(description="Pre-process the Whisparr 3 OpenAPI document.")
    parser.add_argument("--raw-spec", default="spec/openapi.raw.json")
    parser.add_argument("--out-file", default="spec/openapi.generated.json")
    args = parser.parse_args()

    raw_path = resolve_repo_path(args.raw_spec)
    out_path = resolve_repo_path(args.out_file)
    out_dir = os.path.dirname(out_path)
    # Derived from the output file's own directory, so a scratch run cannot overwrite the committed
    # one.
    provenance_path = os.path.join(out_dir, "PROVENANCE.json")

    default_raw = resolve_repo_path("spec/openapi.raw.json")
    default_out = resolve_repo_path("spec/openapi.generated.json")

    print("Pre-process Whisparr 3 openapi -> " + out_path)

    # --- 0. A fixture run must never promote itself onto the committed deliverable ---
    # The two operands take different comparisons on purpose. "Non-default input" is exact, so on
    # Linux spec/OPENAPI.RAW.JSON is not spec/openapi.raw.json. "Committed output path" is
    # case-insensitive on Windows via normcase, because on NTFS a differently-cased spelling IS the
    # committed file.
    if raw_path != default_raw and os.path.normcase(out_path) == os.path.normcase(default_out):
        die(
            "ERROR: REFUSED - a non-default input may not be written to the committed output path. "
            "Pass --out-file with a scratch path too. input {} / output {}".format(raw_path, out_path)
        )
    if not os.path.isfile(raw_path):
        die("ERROR: REFUSED - no input document at " + raw_path + ".")

    # --- 1. Parse ---
    with open(raw_path, "r", encoding="utf-8") as handle:
        document = json.load(handle)
    print("  + parsed {} bytes from {}".format(os.path.getsize(raw_path), raw_path))

    # --- 2. The security transform ---
    # Assigned to the existing key, which keeps security at its position in the root key order.
    # Deleting then adding would move it to the end and inflate the diff against the capture.
    document["security"] = SECURITY
    print("  + root security narrowed to " + json.dumps(SECURITY, separators=(",", ":")))

    # --- 3. Collect the operations ---
    paths = document["paths"]
    operations = []
    for path, item in paths.items():
        for method, operation in item.items():
            if method in HTTP_METHODS:
                operations.append((method.upper() + " " + path, operation.get("operationId"), operation))

    # --- 4. The assertions on the names Whisparr assigns ---
    # Whisparr names every operation itself, so this script no longer derives anything. What it
    # still does is refuse a document whose names the generator cannot turn into a usable class.
    unnamed = [key for key, operation_id, _ in operations if not operation_id]
    if unnamed:
        die(
            "ERROR: REFUSED - {} operations carry no operationId. Whisparr assigns one to every "
            "operation, so a document missing them is either an older release or a regression "
            "upstream. Nothing was staged.".format(len(unnamed)),
            *["    " + key for key in unnamed]
        )
    # Not the generator's FIX_DUPLICATED_OPERATIONID normalizer, which de-duplicates by appending a
    # positional suffix: that masks this assertion, and inserting an operation upstream then moves
    # the suffix onto a different method and renames public API with no diff.
    by_id = {}
    for key, operation_id, _ in operations:
        by_id.setdefault(operation_id, []).append(key)
    collisions = {i: keys for i, keys in by_id.items() if len(keys) > 1}
    if collisions:
        die(
            "ERROR: collision assertion failed - {} operationIds are carried by more than one "
            "operation.".format(len(collisions)),
            *["    {} is assigned to: {}".format(i, ", ".join(keys)) for i, keys in collisions.items()]
            + [
                "  The generator emits one class per tag, so two operations sharing an operationId "
                "are two methods with one name on one class. Report it upstream. Nothing was "
                "staged."
            ]
        )
    # fullmatch: a name the pattern only partly matches is a name the generator sanitizes into one
    # of its own choosing, and a public method would then be named by neither Whisparr nor this
    # repository.
    bad_shape = [(k, i) for k, i, _ in operations if not OPERATION_ID_PATTERN.fullmatch(i)]
    if bad_shape:
        die(
            "ERROR: identifier shape assertion failed - {} names do not match {}. Nothing was "
            "staged.".format(len(bad_shape), OPERATION_ID_PATTERN.pattern),
            *["    {} carries the invalid identifier {}".format(k, i) for k, i in bad_shape]
        )
    print(
        "  + {} operations across {} paths, all named, distinct and valid identifiers".format(
            len(operations), len(paths)
        )
    )

    # --- 5. Write ---
    # Every assertion above has already passed, so this is the first write to anything committed.
    # There is no staging file: json.dumps either serializes the whole document or raises, so a
    # silently truncated write is not a failure mode that needs guarding here.
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    write_json_lf(out_path, document)
    print(
        "  + wrote {} bytes, sha256 {}".format(os.path.getsize(out_path), sha256_file(out_path))
    )

    # --- 6. The manifest ---
    # capture_spec.py rebuilds this file from its own observed fields, so a re-capture DROPS
    # generatedSpecSha256. Deliberate: a new capture invalidates the patched spec, and this script
    # is what puts the field back.
    if os.path.isfile(provenance_path):
        promoted_sha = sha256_file(out_path)
        with open(provenance_path, "r", encoding="utf-8") as handle:
            provenance = json.load(handle)
        provenance["generatedSpecSha256"] = promoted_sha
        write_json_lf(provenance_path, provenance)
        print("  + wrote generatedSpecSha256 {} to {}".format(promoted_sha, provenance_path))

    print("Done. " + out_path)


if __name__ == "__main__":
    main()
