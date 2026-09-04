#!/usr/bin/env python3
"""Capture the Whisparr 3 (Eros) OpenAPI document from a digest-pinned container.

Boots the pinned image, polls the spec endpoint until it answers, asserts the instance really is
Whisparr 3 (Eros), captures the bytes verbatim, and writes spec/PROVENANCE.json beside them.

By digest only. The moving tags point at Whisparr 2, a different application that also serves
/api/v3, so an unpinned pull yields a client that compiles, looks plausible, and is wrong.

    python generator/capture_spec.py
"""

import argparse
import json
import os
import subprocess
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

from _common import die, resolve_repo_path, sha256_file, write_json_lf

# The pinned Whisparr 3.4.0.1387 (eros) digest.
DEFAULT_IMAGE_DIGEST = "sha256:fab920114a75f1c86bbadf24c66f1e35a912ace9c7527e971f1032a569589ee6"
CONTAINER_NAME = "whisparr3-capture"
# Not a credential: a constant handed to a container destroyed at the end of the run and published
# on 127.0.0.1 only. Needed for the status read that feeds provenance; the spec endpoint itself is
# served unauthenticated.
API_KEY = "0123456789abcdef0123456789abcdef"
BASE_URL = "http://localhost:6969"
SPEC_PATH_ON_HOST = "/docs/v3/openapi.json"
SPEC_URL = BASE_URL + SPEC_PATH_ON_HOST
STATUS_URL = BASE_URL + "/api/v3/system/status"


def http_get(url, headers=None, timeout=10):
    """Return (status, body bytes). A refused connection is status 0, not an exception.

    The polling loop below needs to read the status code of a 404, because that is what a
    Whisparr 2 image answers for the whole window. urlopen raises on a 404 instead of returning
    it, so the status is recovered here and reported rather than raised.
    """
    request = urllib.request.Request(url, headers=headers or {})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()
    except (urllib.error.URLError, OSError):
        return 0, b""


def main():
    parser = argparse.ArgumentParser(description="Capture the Whisparr 3 OpenAPI document.")
    parser.add_argument("--image-digest", default=DEFAULT_IMAGE_DIGEST)
    parser.add_argument("--out-file", default="spec/openapi.raw.json")
    # The pinned digest is ready in 13 to 19s. Whisparr 2 never becomes ready and consumes the whole
    # budget, which is the refusal working rather than a hang.
    parser.add_argument("--timeout-sec", type=int, default=90)
    args = parser.parse_args()

    image = "ghcr.io/hotio/whisparr@" + args.image_digest
    spec_path = resolve_repo_path(args.out_file)
    spec_dir = os.path.dirname(spec_path)
    # Derived from the output file's own directory, so a scratch run cannot overwrite the committed
    # one.
    provenance_path = os.path.join(spec_dir, "PROVENANCE.json")

    print("Capture Whisparr 3 openapi -> " + spec_path)
    print("  - image " + image)

    try:
        # -v removes the anonymous volume the image declares for /config, which every run would
        # otherwise leak. 127.0.0.1 explicitly: a bare -p binds 0.0.0.0 and docker punches its own
        # firewall rule, which would put this constant API key on every interface for the whole run.
        subprocess.run(["docker", "rm", "-f", "-v", CONTAINER_NAME], capture_output=True)
        run = subprocess.run(
            ["docker", "run", "-d", "--name", CONTAINER_NAME,
             "-p", "127.0.0.1:6969:6969",
             "-e", "WHISPARR__AUTH__APIKEY=" + API_KEY, image],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if run.returncode != 0:
            die(
                "ERROR: docker run failed for " + image + ". If port 6969 is already bound, free it "
                "rather than repointing this script: it must never capture from an instance it did "
                "not start.",
                (run.stdout or "") + (run.stderr or ""),
            )
        print("  + started {} on host port 6969".format(CONTAINER_NAME))

        # --- 1. Poll the spec endpoint. It needs no authentication ---
        started = time.monotonic()
        last_status = 0
        while time.monotonic() - started < args.timeout_sec:
            last_status, _ = http_get(SPEC_URL, timeout=5)
            if last_status == 200:
                break
            time.sleep(1)
        elapsed = time.monotonic() - started
        if last_status != 200:
            # Naming the observed status and the digest is the whole diagnosis. Whisparr 2 answers
            # 404 here for the entire window, because only Eros serves this endpoint.
            logs = subprocess.run(
                ["docker", "logs", CONTAINER_NAME, "--tail", "40"], capture_output=True, text=True, encoding="utf-8", errors="replace"
            )
            die(
                "ERROR: REFUSED - {} returned HTTP {}, not 200, within {}s for {}.".format(
                    SPEC_URL, last_status, args.timeout_sec, args.image_digest
                ),
                "  A 404 across the whole window means this is not Whisparr 3 (Eros). No spec was "
                "written to " + spec_path + ".",
                (logs.stdout or "") + (logs.stderr or ""),
            )
        print("  + spec endpoint ready after {:.1f}s".format(elapsed))

        # --- 2. Identity assertion. Reached only when a spec IS being served ---
        status_code, status_body = http_get(STATUS_URL, headers={"X-Api-Key": API_KEY}, timeout=10)
        if status_code != 200:
            die(
                "ERROR: REFUSED - the instance serves a spec but answered {} with HTTP {}. Whisparr "
                "3 (Eros) returns 200 there. No spec was written.".format(STATUS_URL, status_code)
            )
        status = json.loads(status_body.decode("utf-8"))
        branch = status.get("branch")
        version = status.get("version")
        # An absent or unparseable version is a failed assertion, not a crash.
        major = None
        if isinstance(version, str):
            head = version.split(".")[0]
            if head.isdigit():
                major = int(head)
        if branch != "eros" or major != 3:
            die(
                "ERROR: REFUSED - the instance reports branch '{}' version '{}'. Required: branch "
                "'eros' and major version 3. No spec was written.".format(branch, version)
            )
        print("  + identity ok - Whisparr {}, branch {}".format(version, branch))

        # --- 3. Capture, byte-verbatim ---
        # The response body is written as bytes and never decoded, so the committed file is exactly
        # what the server sent and its sha256 is the server's.
        spec_status, spec_bytes = http_get(SPEC_URL, timeout=30)
        if spec_status != 200:
            die("ERROR: REFUSED - {} answered HTTP {} on the capture read.".format(SPEC_URL, spec_status))
        if spec_dir:
            os.makedirs(spec_dir, exist_ok=True)
        with open(spec_path, "wb") as handle:
            handle.write(spec_bytes)
        sha = sha256_file(spec_path)
        print("  + captured {} bytes, sha256 {}".format(len(spec_bytes), sha))

        # --- 4. Provenance, from observed values only ---
        # generatedSpecSha256 is deliberately absent: a new capture invalidates the patched spec,
        # and preprocess_spec.py is what puts that field back.
        spec = json.loads(spec_bytes.decode("utf-8"))
        provenance = {
            "capturedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "capturedFrom": SPEC_URL,
            "imageDigest": image,
            "whisparrVersion": version,
            "whisparrBranch": branch,
            "whisparrBuildTime": status.get("buildTime"),
            "whisparrPackageVersion": status.get("packageVersion"),
            "specEndpoint": SPEC_PATH_ON_HOST,
            "specSha256": sha,
            "specBytes": len(spec_bytes),
            "specOpenApiVersion": spec.get("openapi"),
        }
        # A null is not an observation. Without this a Whisparr that renames a status member writes
        # null into the committed manifest and the run still prints Done.
        unobserved = [k for k, v in provenance.items() if v is None or (isinstance(v, str) and not v.strip())]
        if unobserved:
            die(
                "ERROR: REFUSED - provenance would record no observed value for: {}. {} is "
                "untouched.".format(", ".join(unobserved), provenance_path)
            )
        write_json_lf(provenance_path, provenance)
        print("  + wrote " + provenance_path)

        print("Done. " + spec_path)
    finally:
        # Force-remove by name so a failed run cannot leave a stale container holding host port 6969.
        subprocess.run(["docker", "rm", "-f", "-v", CONTAINER_NAME], capture_output=True)


if __name__ == "__main__":
    main()
