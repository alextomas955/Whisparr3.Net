#!/usr/bin/env python3
"""Move this SDK to a new Whisparr version, or re-verify the pinned one.

Runs the whole pipeline in order, stops at the first failure, and names the step that failed and
what to do about it. With no arguments it re-verifies the digest capture_spec.py pins: every gate is
exercised and nothing changes but the capturedAt wall clock in spec/PROVENANCE.json.

--image-digest is forwarded to capture_spec.py only when supplied, so the pin stays there alone
rather than being copied here where the two could drift apart. Each step runs as its own process, so
a child that fails arrives here as an exit code rather than as a traceback.

    python generator/refresh.py --image-digest sha256:0123abcd...
    # Move to a new Whisparr image. Expect an operationId assertion to refuse if the new version
    # moved a path; see its message. Omit --image-digest to re-verify the pinned one.
"""

import argparse
import os
import subprocess
import sys

from _common import REPO_ROOT

GEN_DIR = os.path.dirname(os.path.abspath(__file__))
SOLUTION = os.path.join(REPO_ROOT, "Whisparr3.Net.slnx")
PROJECT = os.path.join(REPO_ROOT, "src", "Whisparr3.Net", "Whisparr3.Net.csproj")
FINDING_MARKER = "has the following vulnerable packages"


def script(name, *extra):
    return [sys.executable, os.path.join(GEN_DIR, name)] + list(extra)


def package_audit():
    """The verdict is read from the transcript text and never from the exit code.

    Measured 2026-09-04: against a probe referencing System.Text.RegularExpressions 4.3.0 this
    command printed a High severity advisory and exited 0, so a gate on the exit code passes a
    finding. --include-transitive covers both frameworks in one pass. The continuous gate is
    Directory.Build.props, where NuGetAudit plus TreatWarningsAsErrors turns NU1901 through NU1904
    into restore errors; this is the point-in-time confirmation of it.
    """
    result = subprocess.run(
        ["dotnet", "list", PROJECT, "package", "--vulnerable", "--include-transitive"],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    transcript = (result.stdout or "") + (result.stderr or "")
    # An exact substring, which is what this verbatim marker needs. A looser match on the word
    # vulnerable is satisfied by the echoed command line itself.
    if FINDING_MARKER in transcript:
        print(transcript)
        print("ERROR: the dependency closure carries a vulnerable package.")
        return 1
    print("  + no vulnerable packages reported across the transitive closure")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Refresh Whisparr3.Net from a Whisparr image.")
    # A Whisparr 3 (eros) image digest. Omitted, capture_spec.py's own pin is used.
    parser.add_argument("--image-digest", default="")
    args = parser.parse_args()

    capture_args = ["--image-digest", args.image_digest] if args.image_digest.strip() else []

    # dotnet localizes its output, so on a non-English runner the marker above would miss and a
    # vulnerable closure would read as clean. Set for this process and its children only.
    os.environ["DOTNET_CLI_UI_LANGUAGE"] = "en"

    # Each step is what to run and the one thing a reader needs to know when it refuses.
    steps = [
        ("capture-spec", script("capture_spec.py", *capture_args),
         "The capture failed, or the identity assertion refused what came back. Check that the "
         "digest names a Whisparr 3 (eros) image and that Docker can pull and boot it. Nothing "
         "downstream ran."),
        ("preprocess-spec", script("preprocess_spec.py"),
         "Most often this is an assertion on the derived operationIds, which means this Whisparr "
         "moved a path. Read which assertion refused: a stale override names a path that has moved, "
         "and a shape or collision failure names an operation that needs an override. Edit "
         "OPERATION_ID_OVERRIDES in preprocess_spec.py and run this script again. The committed "
         "spec was not replaced."),
        ("generate", script("generate.py"),
         "Generation refused or the generator container failed. Its own message says whether the "
         "generated tree was left touched or untouched; read that before re-running."),
        ("render-docs", script("render_docs.py"),
         "The render refused. Most often a path named in render_docs.py has left the spec, which "
         "means Whisparr moved or removed it: the message names which list and which path. Fix the "
         "list and the prose that describes it together, then run this script again. The spec and "
         "the generated tree above are already committed."),
        ("build", ["dotnet", "build", SOLUTION, "-c", "Release", "--nologo"],
         "The regenerated surface does not compile on both target frameworks. "
         "Directory.Build.props treats warnings as errors, so a new warning stops here too. A build "
         "that passes here is also what proves the derivation delivered one method per operation. "
         "Fix it in the spec pre-processing or in the hand-written layer, never inside "
         "src/Whisparr3.Net/."),
        ("package-audit", package_audit,
         "A finding is a finding to report, never a dependency to remove on reflex. All four "
         "shipped packages are required. The transcript above names the package and its advisory."),
    ]

    source = args.image_digest if capture_args else "capture_spec.py's pinned digest"
    print("Refreshing Whisparr3.Net from " + source)

    for name, action, remedy in steps:
        print("==> " + name)
        sys.stdout.flush()
        code = action() if callable(action) else subprocess.run(action).returncode
        if code != 0:
            print("ERROR: refresh stopped at {}, which exited {}.".format(name, code))
            print("  " + remedy)
            sys.exit(1)

    print("Refresh complete. All {} steps passed.".format(len(steps)))


if __name__ == "__main__":
    main()
