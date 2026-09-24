#!/usr/bin/env python3
"""Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

One transform: narrow the root security requirement to the header scheme. Everything else this
script used to do is now correct in the document Whisparr serves.

    python generator/preprocess_spec.py
"""

import json
import os
import re

from _common import die, resolve_repo_path, sha256_file, write_json_lf

RAW_SPEC = resolve_repo_path("spec/openapi.raw.json")
OUT_SPEC = resolve_repo_path("spec/openapi.generated.json")
PROVENANCE = resolve_repo_path("spec/PROVENANCE.json")

# Mandatory auth, header scheme only.
#
# Whisparr declares both of its schemes at the root, which is the OpenAPI spelling for "either
# one". generichost does not read it that way: it emits a call to every declared scheme, so the
# document as served puts the key in the query string of every request, where it reaches access
# logs, proxy logs and Referer headers (upstream openapi-generator issue 24138). Measured
# 2026-09-24 by generating from the untouched capture: all 273 operations call UseInQuery.
#
# The four operations that really are anonymous carry their own empty security list in the document
# and are left alone here.
SECURITY = [{"X-Api-Key": []}]

HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")
# The shape of an operationId the generator will use verbatim.
OPERATION_ID_PATTERN = re.compile(r"[A-Za-z][A-Za-z0-9]*")


def main():
    print("Pre-process Whisparr 3 openapi -> " + OUT_SPEC)

    with open(RAW_SPEC, "r", encoding="utf-8") as handle:
        document = json.load(handle)
    print("  + parsed {} bytes from {}".format(os.path.getsize(RAW_SPEC), RAW_SPEC))

    # Assigned to the existing key, which keeps security at its position in the root key order.
    # Deleting then adding would move it to the end and inflate the diff against the capture.
    document["security"] = SECURITY
    print("  + root security narrowed to " + json.dumps(SECURITY, separators=(",", ":")))

    # The one assertion left. A name the generator cannot use verbatim is one it invents from the
    # path instead, and the run still exits 0: measured 2026-09-24, an operation with no
    # operationId is emitted as ApiV3TagGetAsync and the id "get-Tag.list" is emitted as
    # GetTagListAsync. Both silently rename public API, which is the one failure here that a
    # compile does not catch.
    #
    # Two operations sharing an id is NOT checked here. gen-config.yaml sets validateSpec: true and
    # the generator refuses that document itself, naming the repeated path. Restore this check if
    # that setting is ever turned off.
    unusable = []
    for path, item in document["paths"].items():
        for method, operation in item.items():
            if method not in HTTP_METHODS:
                continue
            operation_id = operation.get("operationId")
            if not operation_id or not OPERATION_ID_PATTERN.fullmatch(operation_id):
                unusable.append("{} {} carries {!r}".format(method.upper(), path, operation_id))
    if unusable:
        die(
            "ERROR: REFUSED - {} operations carry an operationId the generator cannot use "
            "verbatim, so it would name those methods itself. Report it upstream. Nothing was "
            "staged.".format(len(unusable)),
            *["    " + line for line in unusable]
        )

    write_json_lf(OUT_SPEC, document)
    print("  + wrote {} bytes, sha256 {}".format(os.path.getsize(OUT_SPEC), sha256_file(OUT_SPEC)))

    # capture_spec.py rebuilds this file from its own observed fields, so a re-capture DROPS
    # generatedSpecSha256. Deliberate: a new capture invalidates the patched spec, and this script
    # is what puts the field back.
    with open(PROVENANCE, "r", encoding="utf-8") as handle:
        provenance = json.load(handle)
    provenance["generatedSpecSha256"] = sha256_file(OUT_SPEC)
    write_json_lf(PROVENANCE, provenance)

    print("Done. " + OUT_SPEC)


if __name__ == "__main__":
    main()
