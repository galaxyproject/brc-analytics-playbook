#!/usr/bin/env python3
"""Check every environment's build settings against the app-repo branch it tracks.

The app repo moves under us. When it split each site into a standalone Next app
under `sites/`, three things changed at once -- the npm script names, where the
static export lands, and which top-level dirs exist -- and the playbook was
configured for the old shape. The failure modes are asymmetric and both bad:

  * a stale `build_script` fails loudly (`npm error Missing script`)
  * a stale `frontend_out_dir` fails at staging (`mv: cannot stat 'out'`), after
    a full build has already run
  * a stale change-detection pathspec fails SILENTLY -- an unmatched pathspec is
    empty rather than an error, and `failed_when: false` turns that into "no
    frontend changes", so the environment quietly stops deploying while every
    run still reports success

This reads the inventory as Ansible resolves it and checks each environment
against the actual `package.json` of the branch that environment tracks --
following a per-env `repo_url` when one is set, since branches can live on a
fork. It derives the expected export directory from the real `next build
<project>` argument rather than assuming.

Different environments legitimately track branches on opposite sides of a
refactor (dev on `main`, prod on `production`), so there is no single correct
answer to compare against -- hence per-environment resolution.

Usage:  make check-envs        (see the Makefile target)
Reads inventory JSON on stdin, from `ansible-inventory --host <host>`.
Exits non-zero if any environment is misconfigured.
"""

import json
import subprocess
import sys

# Map repo owner -> the git remote in the local app checkout that tracks it.
REMOTE_FOR = {"galaxyproject": "upstream", "dannon": "origin"}


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: check-environments.py <app-repo-path> <frontend-pathspec>")
    app, pathspec = sys.argv[1], sys.argv[2].split()

    inv = json.load(sys.stdin)
    envs = inv.get("brc_environments")
    if not envs:
        print("  (no brc_environments on this host)")
        return 0

    default_build = inv.get("brc_build_script")
    default_repo = inv.get("brc_repo_url", "")

    def git(*args):
        return subprocess.run(["git", "-C", app, *args], capture_output=True, text=True)

    def ref_for(repo, branch):
        for owner, remote in REMOTE_FOR.items():
            if f"/{owner}/" in repo:
                return f"{remote}/{branch}"
        return None

    failures = 0
    for e in envs:
        name, branch = e["name"], e["branch"]
        repo = e.get("repo_url", default_repo)
        build = e.get("build_script", default_build)
        out = e.get("frontend_out_dir", "out")
        cat_src = e.get("catalog_source_dir", "catalog/source/")
        cat_build = e.get("catalog_build_script", "build-brc-db")

        ref = ref_for(repo, branch)
        if ref is None:
            print(f"  {name:<10} unrecognised repo {repo} -- add it to REMOTE_FOR")
            failures += 1
            continue

        got = git("show", f"{ref}:package.json")
        if got.returncode != 0:
            print(f"  {name:<10} {ref:<28} !! not found locally (git fetch first?)")
            failures += 1
            continue
        scripts = json.loads(got.stdout)["scripts"]

        problems = []
        if build not in scripts:
            problems.append(f"build script {build!r} does not exist on {ref}")
        else:
            tail = scripts[build].split("next build", 1)[1].strip().split()
            project = tail[0] if tail and not tail[0].startswith("-") else "."
            expected = "out" if project == "." else f"{project}/out"
            if expected != out:
                problems.append(
                    f"{ref} exports to {expected!r} but frontend_out_dir={out!r}"
                )
        if cat_build not in scripts:
            problems.append(f"catalog script {cat_build!r} does not exist on {ref}")
        if git("cat-file", "-e", f"{ref}:{cat_src.rstrip('/')}").returncode != 0:
            problems.append(f"catalog_source_dir {cat_src!r} is not in {ref}")

        present = [
            p for p in pathspec
            if git("cat-file", "-e", f"{ref}:{p.rstrip('/')}").returncode == 0
        ]
        if not present:
            problems.append(
                "no change-detection path exists on this branch -- updates would "
                "silently never rebuild"
            )

        status = "OK" if not problems else "FAIL"
        if problems:
            failures += 1
        print(f"  {name:<10} {ref:<28} build={build:<16} out={out:<28} [{status}]")
        print(f"             detects via: {' '.join(present) if present else '(none)'}")
        for p in problems:
            print(f"             !! {p}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
