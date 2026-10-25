#!/usr/bin/env python3
"""Integration checks using real Arch packaging tools and read-only AUR fixtures.

Run in the assigned VM:
  python packaging/aur/test-sync.py STABLE_FIXTURE GIT_FIXTURE NEW_WORKSPACE
"""

import os
from pathlib import Path
import shutil
import subprocess
import sys


RECIPES = Path(__file__).resolve().parent
STABLE, GIT, WORK = (Path(p).resolve() for p in sys.argv[1:])
WORK.mkdir()  # Each run preserves all previous evidence.
(WORK / "tmp").mkdir()
os.environ["TMPDIR"] = str(WORK / "tmp")


def run(*args, cwd=WORK, success=True, env=None):
    result = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, env=env, timeout=300)
    print(result.stdout, end="", flush=True)
    if success:
        assert result.returncode == 0, (args, result.returncode)
    else:
        assert result.returncode != 0, args
    return result.stdout


def commit(directory):
    run("git", "add", ".", cwd=directory)
    run("git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
        "commit", "-m", "fixture", cwd=directory)


def fixtures(label):
    parent = WORK / label
    parent.mkdir()
    destinations = []
    for name, fixture in (("atmosphera", STABLE), ("atmosphera-git", GIT)):
        directory = parent / name
        shutil.copytree(fixture, directory)
        run("git", "init", "-b", "master", cwd=directory)
        commit(directory)
        destinations.append(directory)
    return destinations


def sync(recipes, destinations, *extra, success=True):
    return run(sys.executable, str(recipes / "sync.py"), "v0.9.0",
               *(str(d) for d in destinations), *extra, success=success)


baseline = fixtures("baseline")
out = sync(RECIPES, baseline)
assert "atmosphera-git: no change" in out
assert (baseline[1] / "PKGBUILD").read_bytes() == (GIT / "PKGBUILD").read_bytes()
assert (baseline[1] / ".SRCINFO").read_bytes() == (GIT / ".SRCINFO").read_bytes()
assert (baseline[0] / ".SRCINFO").read_bytes() == (STABLE / ".SRCINFO").read_bytes()
for directory in baseline:
    assert run("git", "rev-list", "--count", "HEAD", cwd=directory).strip() == "1"
run("diff", "-u", str(STABLE / "PKGBUILD"), str(baseline[0] / "PKGBUILD"), success=False)
print("PASS: stable metadata/checksum identical; -git byte-identical; no commits/pushes")

changed_recipes = WORK / "changed-recipes"
shutil.copytree(RECIPES, changed_recipes)
metadata = changed_recipes / "metadata.sh"
metadata.write_text(metadata.read_text().replace("  'python'\n", "  'python'\n  'file'\n"))
changed = fixtures("dependency")
sync(changed_recipes, changed)
for directory in changed:
    assert "  'file'\n" in (directory / "PKGBUILD").read_text()
    assert "\tdepends = file\n" in (directory / ".SRCINFO").read_text()
    commit(directory)
assert "pkgrel=13\n" in (changed[1] / "PKGBUILD").read_text()
out = sync(changed_recipes, changed)
assert "atmosphera-git: no change" in out
assert "pkgrel=13\n" in (changed[1] / "PKGBUILD").read_text()
print("PASS: shared dependency reaches both PKGBUILDs/.SRCINFO; bump once; retry no-op")

# Published VCS pkgver is generated and must not trigger a packaging bump.
vcs = fixtures("vcs-version")
recipe = vcs[1] / "PKGBUILD"
recipe.write_text(recipe.read_text().replace("pkgver=0.6.0.r0.g0000000", "pkgver=0.9.0.r7.g1234567"))
commit(vcs[1])
assert "atmosphera-git: no change" in sync(RECIPES, vcs)
print("PASS: generated VCS version does not trigger a recipe publication")

hook_recipes = WORK / "hook-recipes"
shutil.copytree(RECIPES, hook_recipes)
hook = hook_recipes / "atmosphera-git/atmosphera-git.install"
hook.write_text(hook.read_text() + "\n# Fixture hook change\n")
hooks = fixtures("hooks")
sync(hook_recipes, hooks)
assert "pkgrel=13\n" in (hooks[1] / "PKGBUILD").read_text()
assert (hooks[1] / hook.name).read_bytes() == hook.read_bytes()
print("PASS: install-hook-only change is published with a pkgrel bump")

# Reject dirty input before modifying either clone.
dirty = fixtures("dirty")
(dirty[1] / "untracked").write_text("fixture")
before = (dirty[0] / "PKGBUILD").read_bytes()
assert "clone must be clean" in sync(RECIPES, dirty, success=False)
assert (dirty[0] / "PKGBUILD").read_bytes() == before

# Use a real makepkg failure to prove metadata errors cannot be swallowed.
broken_recipes = WORK / "broken-recipes"
shutil.copytree(RECIPES, broken_recipes)
recipe = broken_recipes / "atmosphera-git/PKGBUILD"
recipe.write_text(recipe.read_text() + "\n) invalid syntax\n")
broken = fixtures("broken")
assert "AUR sync FAILED" in sync(broken_recipes, broken, success=False)
for directory in broken:
    assert run("git", "rev-list", "--count", "HEAD", cwd=directory).strip() == "1"
print("PASS: dirty-input and real metadata failures propagate; neither clone committed")
print("ALL AUR SYNC INTEGRATION CHECKS PASSED")
