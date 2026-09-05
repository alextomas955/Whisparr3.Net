#!/usr/bin/env python3
"""Regenerate the Whisparr3.Net client tree from the committed spec, using the pinned generator.

Stages the two inputs into a temporary root, runs the pinned generator image against it, gates the
staged tree, then deletes the five generated subdirectories and copies the new ones back. The
generator never prunes, so the delete is the pruner.

Docker on this machine cannot bind-mount the I: drive. Measured 2026-09-04: a bind mount of an I:
path lists an empty directory and exits 0, so it looks like it worked and is not. Generation
therefore stages under the user temp directory on C:. gen-config.yaml needs no edit, because its
/local-rooted paths already resolve against a mirrored staging root. Do not repair the mount by
restarting Docker Desktop or running wsl --shutdown: this machine hosts live containers.

There is no output-root parameter on purpose. The destination is the whole repository tree, and a
redirect without a promote guard is the fail-open shape this pipeline is hardened against.

    python generator/generate.py
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

from _common import REPO_ROOT, die

# openapi-generator-cli 7.25.0, the pin recorded at the top of generator/gen-config.yaml. By digest
# and never by tag, so a retagged image cannot change this library's public surface.
DEFAULT_IMAGE_DIGEST = "sha256:2ab0a9680222de65dc9d3baf861aa02b99e1b80c211d8221ebf3ae8f8a102524"
# The generated tree is these five subdirectories, not src/Whisparr3.Net itself: the hand-owned
# csproj sits beside them and survives every run. One list, so the delete set and the copy set cannot
# drift apart.
GENERATED_SUBDIRS = ("Api", "Client", "Extensions", "Logging", "Model")
# The two generated subdirectories whose contents are a function of the spec, one file per schema
# and one per tag. Everything under Client, Extensions and Logging is generator scaffolding whose
# file list depends on the pinned image rather than on the API.
SPEC_DRIVEN_SUBDIRS = ("Model", "Api")
# The generator emits one extra file into Api/ that belongs to no tag: the shared IApi marker.
UNTAGGED_API_FILES = frozenset({"IApi.cs"})
HTTP_METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")


def expected_from_spec(spec_path):
    """The Model/ and Api/ file names the committed spec implies.

    Derived, never pinned. The count of operations Whisparr declares moves between releases and
    this repository has no business asserting a particular one. What it can assert is the mapping,
    which is exact in both directions: one Model/<Schema>.cs per schema in components.schemas, and
    one Api/<Tag>Api.cs per tag any operation carries. A generation that stops early fails this
    because names are missing, which is the failure the old pinned count existed to catch.
    """
    with open(spec_path, "r", encoding="utf-8") as handle:
        spec = json.load(handle)

    models = {name + ".cs" for name in spec.get("components", {}).get("schemas", {})}
    tags = set()
    for item in spec["paths"].values():
        for method, operation in item.items():
            if method in HTTP_METHODS:
                tags.update(operation.get("tags") or [])
    return {"Model": models, "Api": {tag + "Api.cs" for tag in tags} | set(UNTAGGED_API_FILES)}


def generated_cs_files(package_root):
    """Count over the five generated subdirectories, never recursively over the package root: after
    any build obj/<config>/<tfm>/Whisparr3.Net.AssemblyInfo.cs sits under it and would be counted.
    """
    found = []
    for subdir in GENERATED_SUBDIRS:
        for dirpath, _, filenames in os.walk(os.path.join(package_root, subdir)):
            found.extend(os.path.join(dirpath, f) for f in filenames if f.endswith(".cs"))
    return found


def main():
    parser = argparse.ArgumentParser(description="Regenerate the Whisparr3.Net client tree.")
    parser.add_argument("--image-digest", default=DEFAULT_IMAGE_DIGEST)
    args = parser.parse_args()

    image = "openapitools/openapi-generator-cli@" + args.image_digest
    pkg_dir = os.path.join(REPO_ROOT, "src", "Whisparr3.Net")
    gen_meta_dir = os.path.join(REPO_ROOT, ".openapi-generator")
    stage = tempfile.mkdtemp(prefix="whisparr3-generate-")
    stage_pkg_dir = os.path.join(stage, "src", "Whisparr3.Net")

    print("Generate Whisparr3.Net client -> " + pkg_dir)
    print("  - image " + image)

    # False until step 3 starts deleting. The handler branches on it, because whether the repository
    # is mid-replace is the one fact a caller needs and a bare traceback does not carry.
    tree_touched = False

    try:
        # --- 1. Stage the two inputs, mirroring the repository layout ---
        os.makedirs(os.path.join(stage, "spec"))
        os.makedirs(os.path.join(stage, "generator"))
        shutil.copy2(os.path.join(REPO_ROOT, "spec", "openapi.generated.json"), os.path.join(stage, "spec"))
        shutil.copy2(os.path.join(REPO_ROOT, "generator", "gen-config.yaml"), os.path.join(stage, "generator"))

        # --- 2. Run the pinned image, then gate the staged tree before anything committed is
        # deleted ---
        # The image runs as uid 0. On a Linux runner that makes every directory it creates inside
        # the bind mount root-owned, and the cleanup below then cannot unlink under them. Windows
        # bind mounts carry no POSIX ownership, so the flag is added only where it means something.
        user_args = [] if os.name == "nt" else ["--user", "{}:{}".format(os.getuid(), os.getgid())]
        # encoding is pinned rather than left to text=True, which decodes with the locale
        # codec. On a Windows console that is cp1252, and this image emits bytes it cannot
        # decode: the reader thread dies and the failure branch below then has no output to
        # print.
        run = subprocess.run(
            ["docker", "run", "--rm"] + user_args + ["-v", stage + ":/local", image,
             "generate", "-c", "/local/generator/gen-config.yaml"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
        )
        if run.returncode != 0:
            print((run.stdout or "") + (run.stderr or ""))
            print("ERROR: REFUSED - the generator exited {} for {}. Nothing in {} was touched.".format(
                run.returncode, image, pkg_dir))
            sys.exit(run.returncode)
        staged_cs = generated_cs_files(stage_pkg_dir)
        # A subdirectory the generator did not emit at all is invisible to the count, because
        # generated_cs_files walks a missing one as empty. Step 4 would then fail partway through the
        # copy, after the delete, which is the expensive place to find out.
        missing = [d for d in GENERATED_SUBDIRS if not os.path.isdir(os.path.join(stage_pkg_dir, d))]
        if missing:
            die(
                "ERROR: REFUSED - the staged tree is missing {} of the five generated "
                "subdirectories: {}. Nothing in {} was touched.".format(
                    len(missing), ", ".join(missing), pkg_dir)
            )
        # Name-for-name against the spec, not a count against a literal. Whisparr moves its
        # operation count between releases and this repository asserts no particular one.
        expected = expected_from_spec(os.path.join(stage, "spec", "openapi.generated.json"))
        problems = []
        for subdir, want in expected.items():
            have = {f for f in os.listdir(os.path.join(stage_pkg_dir, subdir)) if f.endswith(".cs")}
            for name in sorted(want - have):
                problems.append("    {}/{} is implied by the spec and was not generated".format(subdir, name))
            for name in sorted(have - want):
                problems.append("    {}/{} was generated and the spec implies no such file".format(subdir, name))
        if problems:
            die(
                "ERROR: REFUSED - the staged tree does not match the spec it was generated from, "
                "in {} file(s). Nothing in {} was touched.".format(len(problems), pkg_dir),
                *problems[:20]
            )
        for subdir in ("Client", "Extensions", "Logging"):
            if not any(f.endswith(".cs") for f in os.listdir(os.path.join(stage_pkg_dir, subdir))):
                die("ERROR: REFUSED - {}/ holds no .cs file. Nothing in {} was touched.".format(
                    subdir, pkg_dir))
        print("  + generator exited 0, staged {} .cs files, every Model/ and Api/ name matches "
              "the spec".format(len(staged_cs)))

        # --- 3. Replace, never merge ---
        # Copying into an existing target merges: it neither replaces the target nor nests inside
        # it, so without this delete a stale file inside Api/ survives the copy and compiles. Set
        # before the first unlink: from here to the end of step 4 the repository is mid-replace.
        tree_touched = True
        for subdir in GENERATED_SUBDIRS:
            shutil.rmtree(os.path.join(pkg_dir, subdir), ignore_errors=True)
        shutil.rmtree(gen_meta_dir, ignore_errors=True)

        # --- 4. Copy back exactly what the generator owns, and nothing else ---
        # Not the whole staged tree, which would drag spec/ and generator/ over the committed
        # originals.
        os.makedirs(pkg_dir, exist_ok=True)
        for subdir in GENERATED_SUBDIRS:
            shutil.copytree(os.path.join(stage_pkg_dir, subdir), os.path.join(pkg_dir, subdir))
        shutil.copytree(os.path.join(stage, ".openapi-generator"), gen_meta_dir)
        shutil.copy2(os.path.join(stage, ".openapi-generator-ignore"), REPO_ROOT)

        copied_cs = generated_cs_files(pkg_dir)
        if len(copied_cs) != len(staged_cs):
            die(
                "ERROR: copied {} .cs files but staged {}. The tree under {} is now partially "
                "written. Recovery is to re-run generate.py, which deletes and rewrites the whole "
                "tree.".format(len(copied_cs), len(staged_cs), pkg_dir)
            )
        print("  + copied {} .cs files into {}".format(len(copied_cs), pkg_dir))
        print("Done. " + pkg_dir)
    except SystemExit:
        raise
    except Exception as error:
        # Without this, a failure between the delete and the count assertion escapes as a raw
        # traceback that says nothing about the repository, by which point the five subdirectories
        # are gone. This is the only script here that deletes a committed deliverable.
        if tree_touched:
            present = generated_cs_files(pkg_dir)
            die(
                "ERROR: generate.py stopped after it had begun replacing the tree: {}".format(error),
                "  {} now holds {} .cs files and the tree is incomplete. Recovery is to re-run "
                "generate.py, or git -C {} checkout -- src/Whisparr3.Net .openapi-generator "
                ".openapi-generator-ignore".format(pkg_dir, len(present), REPO_ROOT),
            )
        die(
            "ERROR: generate.py stopped before it had begun replacing the tree: {}. Nothing in {} "
            "was touched.".format(error, pkg_dir)
        )
    finally:
        # Non-fatal on purpose. An error here would replace the pending exit code and rewrite the
        # verdict of the run above it. A leftover staging root is a nuisance to name, not a reason to
        # call a correct generation a failure.
        shutil.rmtree(stage, ignore_errors=True)
        if os.path.isdir(stage):
            print("  ! could not remove the staging root " + stage + ". Remove it by hand. The verdict above stands.")


if __name__ == "__main__":
    main()
