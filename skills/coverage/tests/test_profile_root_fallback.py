"""Pins the repo-root testing-profile fallback of the two Python callers (coverage-s13, Q33): profile-init.py
resolve_profile and _coverage_lib.profile_module_map. Layer: unit on temp project dirs, no network and no docker.
The contract: .context/ wins, a tracked <root>/testing-profile.md is the fallback, neither means no profile; the answer
depends only on the root path given, so it holds in a plain dir, a dir with no git at all, and a linked git worktree."""
import importlib.util
import os
import pathlib
import shutil
import subprocess
import tempfile
import unittest

SKILLS = pathlib.Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PROFILE_INIT = load("profile_init", SKILLS / "coverage" / "scripts" / "profile-init.py")
COVERAGE_LIB = load("coverage_lib", SKILLS / "audit" / "scripts" / "coverage" / "_coverage_lib.py")


def profile(module_map):
    return f"---\nproject_slug: p\nmodule_map: {module_map}\n---\n"


class RootFallback(unittest.TestCase):
    def roots(self, tmp):
        """(label, root): a plain dir with no git, and a linked worktree of a real repo."""
        plain = os.path.join(tmp, "plain")
        os.makedirs(plain)
        out = [("no git", plain)]
        if shutil.which("git"):
            main, wt = os.path.join(tmp, "main"), os.path.join(tmp, "wt")
            git = ["git", "-c", "user.email=t@t", "-c", "user.name=t"]
            subprocess.run(["git", "init", "-q", main], check=True)
            subprocess.run(git + ["-C", main, "commit", "-q", "--allow-empty", "-m", "i"], check=True)
            subprocess.run(["git", "-C", main, "worktree", "add", "-q", wt], check=True)
            out.append(("git worktree", wt))
        return out

    def test_context_wins_then_root_file_then_none_for_both_callers(self):
        with tempfile.TemporaryDirectory() as tmp:
            for label, root in self.roots(tmp):
                with self.subTest(label):
                    ctx = pathlib.Path(root, ".context", "profiles", "testing.md")
                    top = pathlib.Path(root, "testing-profile.md")
                    # neither
                    path, why = PROFILE_INIT.resolve_profile(root)
                    self.assertIsNone(path)
                    self.assertIn(str(top), why)
                    self.assertIn(str(ctx), why)
                    self.assertIsNone(COVERAGE_LIB.profile_module_map(root))
                    # only the tracked root file
                    top.write_text(profile("root-map.json"))
                    self.assertEqual(PROFILE_INIT.resolve_profile(root), (str(top), None))
                    self.assertEqual(COVERAGE_LIB.profile_module_map(root), os.path.join(root, "root-map.json"))
                    # both: .context/ wins
                    ctx.parent.mkdir(parents=True)
                    ctx.write_text(profile("ctx-map.json"))
                    self.assertEqual(PROFILE_INIT.resolve_profile(root), (str(ctx), None))
                    self.assertEqual(COVERAGE_LIB.profile_module_map(root), os.path.join(root, "ctx-map.json"))

    def test_a_directory_named_like_the_root_file_is_not_a_profile(self):
        with tempfile.TemporaryDirectory() as root:
            os.makedirs(os.path.join(root, "testing-profile.md"))
            self.assertIsNone(PROFILE_INIT.resolve_profile(root)[0])
            self.assertIsNone(COVERAGE_LIB.profile_module_map(root))

    def test_a_context_profile_without_module_map_does_not_fall_through_to_the_root_file(self):
        with tempfile.TemporaryDirectory() as root:
            ctx = pathlib.Path(root, ".context", "profiles", "testing.md")
            ctx.parent.mkdir(parents=True)
            ctx.write_text("---\nname: testing\n---\n")
            pathlib.Path(root, "testing-profile.md").write_text(profile("root-map.json"))
            self.assertIsNone(COVERAGE_LIB.profile_module_map(root))


if __name__ == "__main__":
    unittest.main()
