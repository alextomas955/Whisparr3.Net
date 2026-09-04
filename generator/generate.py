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
# What the pinned image produces from the committed spec. A constant and never a parameter, since a
# caller-supplied count makes the gate a tautology. Without it a generation emitting ten files
# replaces the committed 262 at exit 0. Move it in the same commit that moves the tree.
EXPECTED_CS = 262


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
        if len(staged_cs) != EXPECTED_CS or missing:
            die(
                "ERROR: REFUSED - the staged tree holds {} .cs files across the five generated "
                "subdirectories, expected {}, with {} subdirectories absent. Nothing in {} was "
                "touched.".format(len(staged_cs), EXPECTED_CS, len(missing), pkg_dir)
            )
        print("  + generator exited 0, staged {} .cs files".format(len(staged_cs)))

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
                "  {} now holds {} .cs files where a complete tree holds {}. Recovery is to re-run "
                "generate.py, or git -C {} checkout -- src/Whisparr3.Net .openapi-generator "
                ".openapi-generator-ignore".format(pkg_dir, len(present), EXPECTED_CS, REPO_ROOT),
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
