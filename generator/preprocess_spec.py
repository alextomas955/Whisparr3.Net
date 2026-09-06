#!/usr/bin/env python3
"""Pre-process the captured Whisparr 3 (Eros) OpenAPI document into the spec the generator reads.

T1 repairs root security, T2 deletes the malformed paths["/"], T3 derives an operationId for
every operation from the document itself, and T4 removes the prose Whisparr authored.

The derivation is devopsarr's assign_operation_id.py, the algorithm behind the Go, Python and
TypeScript *arr clients. OPERATION_ID_OVERRIDES names the 13 operations it cannot get right from
the URL alone, mostly abbreviations only a human can expand: alttitle is AlternativeTitle.

Nothing here pins a name against upstream change. If Whisparr renames a path, the derived method
name follows it and the break surfaces in a consumer's build. That trade was accepted in exchange
for deleting a committed name map that had to be reviewed on every version bump.

    python generator/preprocess_spec.py
"""

import argparse
import http
import json
import os
import re

from _common import die, resolve_repo_path, sha256_file, write_json_lf

# Mandatory auth, header scheme only. Both halves are load-bearing.
# Not optional: Whisparr's Startup.cs pins the fallback policy to the API-key scheme and consults
# neither AuthenticationMethod nor AuthenticationRequired, and no key measures 401 under every
# permissive configuration. A leading empty requirement is the OpenAPI spelling for "optional".
# Header only, though Whisparr also declares the query scheme: generichost does not treat the two as
# alternatives but emits a call to every declared scheme, so the both-schemes form put the key in
# the URL of every request, where it reaches access logs, proxy logs and Referer headers
# (upstream openapi-generator issue 24138).
SECURITY = [{"X-Api-Key": []}]

HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")

# The two keys OpenAPI uses for human prose. T4 removes them, for a licensing reason rather than a
# technical one: Whisparr is GPL-3.0, these strings are written by hand in its C# source, and
# openapi-generator copies them verbatim into the XML documentation this MIT-licensed package
# ships. Removing them here keeps that prose out of the package.
#
# What this does NOT remove, and cannot: schema names, property names and the shape of the API,
# which the generated types are built from. Those carry a far weaker copyright claim than authored
# prose, and T3 derives the operation names from the URLs rather than taking them from upstream.
# The removal narrows the question rather than answering all of it.
PROSE_KEYS = ("summary", "description")


def reason_phrase(status):
    """The standard phrase for a response status key, derived and never taken from the document."""
    if not status.isdigit():
        die(
            "ERROR: REFUSED - the response key {!r} is not a numeric status, so T4 cannot derive a "
            "description for it. Every key in the captured spec was numeric when this was written. "
            "Decide what this response should say and add the rule. Nothing was staged.".format(
                status)
        )
    return http.HTTPStatus(int(status)).phrase


def strip_prose(node, kind="plain", status=None):
    """Remove every authored summary and description from the document.

    A Response Object must carry a description and openapi-generator validates what it is given, so
    those are REPLACED rather than deleted, with the standard reason phrase for the status key they
    sit under. That phrase is derived from the key, so nothing upstream wrote survives.

    Replacing rather than keeping matters and was measured. 265 of the captured response
    descriptions already read "OK", which made deletion-with-an-exemption look safe. The other 17
    are authored sentences: "Performer with the specified foreign ID not found", "Studios found and
    returned, or an empty array". Exempting response objects wholesale left all 17 in the package.

    kind tracks position rather than content, because "responses" names a map whose VALUES are the
    protected objects, not the map itself and not everything below it. A schema nested inside a
    response object is still stripped.
    """
    removed = 0

    if isinstance(node, dict):
        if kind == "response-object":
            derived = reason_phrase(status)
            if node.get("description") != derived:
                removed += 1
            node["description"] = derived
        else:
            for key in PROSE_KEYS:
                if key in node:
                    del node[key]
                    removed += 1

        for key, value in node.items():
            if kind == "responses-map":
                removed += strip_prose(value, "response-object", key)
            elif key == "responses":
                removed += strip_prose(value, "responses-map")
            else:
                removed += strip_prose(value, "plain")
    elif isinstance(node, list):
        for value in node:
            removed += strip_prose(value, kind, status)

    return removed
# A valid C# identifier of the shape this library's public method names take. Anchored on purpose.
OPERATION_ID_PATTERN = re.compile(r"[A-Z][A-Za-z0-9]*")

# The 13 operations the derivation cannot name from the URL, keyed "METHOD /path". Every other name
# in the SDK is computed.
#
# GET /feed/v3/calendar/whisparr.ics is the one entry that is not cosmetic. It derives to
# GetFeedV3CalendarWhisparr.ics, which is not a C# identifier, and the shape assertion below refuses
# it. The rest expand an abbreviation or a lower-cased run the URL does not delimit.
OPERATION_ID_OVERRIDES = {
    "GET /{path}": "GetStaticResourceByPath",
    "GET /api": "GetApiInfo",
    "GET /api/v3/alttitle": "ListAlternativeTitle",
    "GET /api/v3/alttitle/{id}": "GetAlternativeTitleById",
    "GET /api/v3/filesystem/mediafiles": "GetFileSystemMediaFiles",
    "GET /api/v3/importlist/movie": "GetImportListMovie",
    "GET /api/v3/mediacover/{movieId}/{filename}": "GetMediaCoverByMovieIdAndFilename",
    "GET /api/v3/movie/listbyperformerforeignid": "ListMovieByPerformerForeignId",
    "GET /api/v3/movie/listbystudioforeignid": "ListMovieByStudioForeignId",
    "GET /api/v3/qualityprofile/schema": "GetQualityProfileSchema",
    "GET /feed/v3/calendar/whisparr.ics": "GetCalendarFeed",
    "GET /login": "GetLoginPage",
    "POST /api/v3/importlist/movie": "CreateImportListMovie",
}


def returns_json_array(operation):
    """devopsarr's list rule keys on the 200 response declaring a JSON array."""
    node = operation
    for key in ("responses", "200", "content", "application/json", "schema", "type"):
        if not isinstance(node, dict):
            return False
        node = node.get(key)
    return node == "array"


def derive_operation_id(method, path, tag, array):
    """devopsarr's assign_operation_id.py, ported with two fixes.

    This iterates the segment list backwards in the placeholder-removal loop, because devopsarr's
    forward loop mutates the list it is enumerating and a removal makes it skip the following
    element. And the POST test-verb rule spells testall as testAll, so the five /testall endpoints
    derive TestAllIndexer rather than TestallIndexer without needing five override entries.
    """
    parts = re.split(r"/|-", re.sub(r"^/api/v\d/(.*)$", r"\1", path))

    if parts[-1].startswith("{"):
        parts[-1] = parts[-1].strip("{}")
        parts.insert(len(parts) - 1, "by")
    verb = method
    tail_is_by_id = len(parts) > 1 and parts[-2] == "by"
    if method == "delete" and tail_is_by_id:
        del parts[-2:]
    if method == "put" and tail_is_by_id:
        verb = "update"
        del parts[-2:]
    if method == "post":
        verb = "create"
        if parts[-1].startswith("test"):
            verb = "testAll" if parts[-1] == "testall" else parts[-1]
            del parts[-1]
    if method == "get" and array:
        verb = "list"
    if len(parts) > 1 and parts[0] == "config":
        parts[0] = parts[1] + "config"
        del parts[1]
    if len(parts) > 1 and parts[1] == "settings":
        del parts[1]
    for i in range(len(parts) - 1, -1, -1):
        if parts[i].startswith("{"):
            del parts[i]
        elif parts[i].lower() == tag.lower():
            parts[i] = tag
    parts.insert(0, verb)
    return "".join(p[0].upper() + p[1:] for p in parts if p)


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

    # --- 2. T1, root security ---
    # Assigned to the existing key, which keeps security at its position in the root key order.
    # Deleting then adding would move it to the end and inflate the diff against the capture.
    document["security"] = SECURITY
    print("  + T1 root security set to " + json.dumps(SECURITY, separators=(",", ":")))

    # --- 3. T2, the malformed root path ---
    # Assert the key was there. Deleting a key that was already gone would produce a plausible
    # spec from a document this pipeline has never seen.
    paths = document["paths"]
    # Counted before the delete, so step 7 can check the output against this input rather than
    # against a number typed into this file. Whisparr adds and removes operations between releases;
    # what has to hold is that this script removed exactly the root path and nothing else.
    operations_in = sum(1 for item in paths.values() for m in item if m in HTTP_METHODS)
    if "/" not in paths:
        die(
            'ERROR: REFUSED - paths["/"] is not present, so ' + raw_path
            + " is not what this pipeline expects. Nothing was written."
        )
    root_operations = sum(1 for m in paths["/"] if m in HTTP_METHODS)
    del paths["/"]
    expected_operations = operations_in - root_operations
    print('  + T2 deleted paths["/"] and its {} operation(s), {} path items remain'.format(
        root_operations, len(paths)))

    # --- 4. Derive a name for every operation ---
    operations = []
    overrides_used = set()
    for path, item in paths.items():
        if not isinstance(item, dict):
            die("ERROR: REFUSED - the path item " + path + " is not a JSON object. Nothing was written.")
        for method, operation in item.items():
            if method not in HTTP_METHODS:
                continue
            if not isinstance(operation, dict):
                die(
                    "ERROR: REFUSED - the operation {} {} is not a JSON object. Nothing was staged.".format(
                        method, path
                    )
                )
            key = method.upper() + " " + path
            if key in OPERATION_ID_OVERRIDES:
                operation_id = OPERATION_ID_OVERRIDES[key]
                overrides_used.add(key)
            else:
                tags = operation.get("tags") or []
                tag = tags[0] if tags and isinstance(tags[0], str) else ""
                operation_id = derive_operation_id(method, path, tag, returns_json_array(operation))
            operations.append((key, operation_id, operation))
    print(
        "  + derived {} operationIds, {} of them from the override table".format(
            len(operations), len(overrides_used)
        )
    )

    # --- 5. The assertions the derivation makes necessary ---
    # An override that matches no operation is the only remaining signal that Whisparr moved a path.
    stale = [k for k in OPERATION_ID_OVERRIDES if k not in overrides_used]
    if stale:
        die(
            "ERROR: {} override entries match no operation in this spec. Whisparr has moved or "
            "removed a path, so the name it pinned is now derived instead. Nothing was "
            "staged.".format(len(stale)),
            *["    {} -> {}".format(k, OPERATION_ID_OVERRIDES[k]) for k in stale]
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
                "are two methods with one name on one class. Add an override for one of them. "
                "Nothing was staged."
            ]
        )
    # fullmatch, and the pattern carries no IGNORECASE: a case-insensitive match would accept
    # listMovie and pass a name the generator then sanitizes into one of its own choosing. This is
    # the assertion that catches GetFeedV3CalendarWhisparr.ics.
    bad_shape = [(k, i) for k, i, _ in operations if not OPERATION_ID_PATTERN.fullmatch(i)]
    if bad_shape:
        die(
            "ERROR: identifier shape assertion failed - {} names do not match {}. Add an override "
            "for each. Nothing was staged.".format(len(bad_shape), OPERATION_ID_PATTERN.pattern),
            *["    {} derived the invalid identifier {}".format(k, i) for k, i in bad_shape]
        )
    print(
        "  + stale-override, collision and shape assertions passed - {} distinct "
        "operationIds".format(len(by_id))
    )

    # --- 6. T3, assign ---
    # Added as a new last key, which is deterministic run to run.
    for _, operation_id, operation in operations:
        operation["operationId"] = operation_id
    print("  + T3 assigned {} operationIds".format(len(operations)))

    # --- 7. T4, remove the prose Whisparr authored ---
    # After T3, so the operationIds it assigned are already in place; strip_prose does not touch
    # them. The count is reported rather than asserted against a pinned number, for the same reason
    # the census below is computed rather than pinned: Whisparr documents more of its API between
    # releases, and that should not fail this pipeline.
    # info is excluded. Its description reads "Whisparr API docs", three generic words naming the
    # API rather than prose describing it, and the generator stamps that line into the header of
    # every file it writes. Removing it does not substitute nothing: the generator falls back to
    # "No description provided (generated by Openapi Generator ...)", which is a worse header in
    # 246 files and buries the real change in a diff five times its size.
    prose_removed = sum(
        strip_prose(value) for key, value in document.items() if key != "info"
    )
    print("  + T4 removed or replaced {} authored prose fields, info untouched".format(
        prose_removed))

    # --- 8. The census ---
    # Against the input, not against a pinned total. This asserts that T2 is the only thing that
    # changed the operation count, which is the property that matters. A release that adds ten
    # operations passes; a bug that drops one does not.
    if len(operations) != expected_operations:
        die(
            "ERROR: REFUSED - the patched document carries {} operations. The input carried {} and "
            "T2 removed {}, so {} were expected. Nothing was staged.".format(
                len(operations), operations_in, root_operations, expected_operations)
        )
    print("  + census: {} in, {} removed by T2, {} out".format(
        operations_in, root_operations, len(operations)))

    # --- 9. Write ---
    # Every assertion above has already passed, so this is the first write to anything committed.
    # There is no staging file: json.dumps either serializes the whole document or raises, so a
    # silently truncated write is not a failure mode that needs guarding here.
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    write_json_lf(out_path, document)
    print(
        "  + wrote {} bytes, sha256 {}".format(os.path.getsize(out_path), sha256_file(out_path))
    )

    # --- 10. The manifest ---
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
