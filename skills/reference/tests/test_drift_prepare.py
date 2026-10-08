"""Tests for scripts/drift/prepare.py: which code units a reference covers.

Layer: integration on real git fixtures (the contract is the work dir it writes)."""
import contextlib
import io
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "scripts", "drift"))
import prepare  # noqa: E402

PAD = "# pad\n" * 70  # about 100 estimated tokens


def write(root, rel, content):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(content)


class PrepareTest(unittest.TestCase):
    def setUp(self):
        self.fresh()

    def fresh(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = os.path.join(tmp.name, "proj")
        self.work = os.path.join(tmp.name, "work")
        os.makedirs(self.root)

    def run_prepare(self, code, refs, budget=prepare.BUDGET, repos=(), work=None):
        """Write the fixture, commit it (nested `repos` get their own git repo), run prepare."""
        for rel, c in code.items():
            write(self.root, rel, c)
        for name, c in refs.items():
            write(self.root, f".context/references/{name}", c)
        g = ["-c", "user.email=t@t", "-c", "user.name=t"]
        for r in [".", *repos]:
            d = os.path.join(self.root, r)
            os.makedirs(d, exist_ok=True)
            skip = [f":(exclude){x}" for x in repos if r == "."]
            subprocess.run(["git", "-C", d, *g, "init", "-q"], check=True)
            subprocess.run(["git", "-C", d, *g, "add", "-A", "--", ".", *skip], check=True)
            subprocess.run(["git", "-C", d, *g, "commit", "-qm", "c", "--allow-empty"],
                           check=True, capture_output=True)
        return prepare.prepare(self.root, work or self.work, budget)

    def kept(self, m):
        return {u["unit"]: u for u in m["units"]}

    def test_path_cite_keeps_unit_and_uncovered_unit_is_dropped(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"billing.md": "Payment lives in code/billing/pay.py:12.\n"}, budget=150)
        k = self.kept(m)
        self.assertEqual(list(k), ["code/billing"])
        self.assertEqual(k["code/billing"]["references"], [".context/references/billing.md"])
        listed = pathlib.Path(self.work, "units", "code-billing.txt").read_text()
        self.assertEqual(listed, "code/billing/pay.py\n")
        self.assertFalse(os.path.exists(os.path.join(self.work, "units", "code-auth.txt")))

    def test_path_cite_is_not_a_prefix_match(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"x.md": "See code/billing/pay.pyc, code/billing/pay.py.bak and code/billing/sub/pay.py\n"}, budget=150)
        self.assertEqual(m["units"], [])

    def test_directory_cite_keeps_unit(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"auth.md": "The auth module (code/auth/) handles login.\n"}, budget=150)
        self.assertEqual(list(self.kept(m)), ["code/auth"])

    def test_symbol_cite_keeps_unit(self):
        m = self.run_prepare(
            {"code/billing/pay.py": "def charge_card():\n    pass\n" + PAD,
             "code/auth/login.py": PAD},
            {"pay.md": "Call `charge_card()` to bill.\n"}, budget=150)
        self.assertEqual(list(self.kept(m)), ["code/billing"])

    def test_symbol_rules(self):
        d = "def {}():\n    pass\n"
        rows = [
            ("not in backticks", {"code/live/a.py": d.format("charge_card") + PAD},
             "charge_card is mentioned without ticks.", []),
            ("3 characters is too short", {"code/live/a.py": d.format("run") + PAD},
             "`run` is cited.", []),
            ("exactly 4 characters is kept",
             {"code/live/a.py": d.format("scan") + PAD, "code/other/b.py": PAD},
             "`scan` is cited.", ["code/live"]),
            ("defined in 3 units covers all 3",
             {"code/live/a.py": d.format("setup_x") + PAD, "_archive/old/a.py": d.format("setup_x") + PAD,
              "code/cron/a.py": d.format("setup_x") + PAD, "_archive/new/b.py": PAD},
             "`setup_x` is cited.", ["_archive/old", "code/cron", "code/live"]),
            ("plain word defined in 2 units covers none",
             {"code/live/a.py": d.format("close") + PAD, "code/cron/a.py": d.format("close") + PAD},
             "`close` is cited.", []),
            ("camelCase defined in 2 units covers both",
             {"code/live/a.js": "function handleBlur() {}\n" + PAD,
              "code/cron/a.js": "function handleBlur() {}\n" + PAD},
             "`handleBlur` is cited.", ["code/cron", "code/live"]),
            ("defined in 4 units covers none",
             {f"{x}/a.py": d.format("setup_x") + PAD for x in ("code/live", "_archive/old", "code/cron", "code/z")},
             "`setup_x` is cited.", []),
        ]
        for name, code, ref, want in rows:
            with self.subTest(name):
                self.fresh()
                m = self.run_prepare(code, {"x.md": ref + "\n"}, budget=150)
                self.assertEqual(sorted(self.kept(m)), want)

    def test_covers_header_with_a_file_path_keeps_unit(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"a.md": '---\ncovers: "routes:/pay, apps: code/auth/login.py"\n---\nBody.\n'}, budget=150)
        k = self.kept(m)
        self.assertEqual(sorted(k), ["code/auth"])
        self.assertEqual(k["code/auth"]["references"], [".context/references/a.md"])

    def test_covers_item_is_expanded_through_the_profile_paths_template(self):
        profile = ("# Profile\n\n```census\naxis: apps\nlabel: apps\ncommand: echo billing\n"
                   "paths: code/apps/{item}\n```\n")
        m = self.run_prepare(
            {"code/apps/billing/pay.py": PAD, "code/apps/auth/login.py": PAD},
            {"00-profile.md": profile, "a.md": '---\ncovers: "apps:billing"\n---\nBody.\n'},
            budget=150)
        self.assertEqual(list(self.kept(m)), ["code/apps/billing"])

    def test_repo_relative_cite_and_covers_item_need_a_slash_and_match_nested_repo(self):
        code = {"code/backend/apps/x/m.py": PAD, "code/backend/apps/y/n.py": PAD,
                "code/backend/top.py": PAD}
        refs = {"a.md": "Cites `apps/x/m.py` and top.py.\n",
                "b.md": '---\ncovers: "frontend: apps/y"\n---\nBody.\n'}
        m = self.run_prepare(code, refs, budget=150, repos=["code/backend"])
        k = self.kept(m)
        self.assertEqual(sorted(k), ["code/backend/apps/x", "code/backend/apps/y"])
        self.assertEqual(k["code/backend/apps/x"]["references"], [".context/references/a.md"])
        self.assertEqual(k["code/backend/apps/y"]["references"], [".context/references/b.md"])

    def test_at_alias_cite_resolves_to_src_of_the_repo(self):
        code = {"code/web/src/x/y.js": PAD, "code/web/src/z/q.js": PAD}
        m = self.run_prepare(code, {"a.md": "Imported as `@/x/y.js`.\n"}, budget=150,
                             repos=["code/web"])
        self.assertEqual(list(self.kept(m)), ["code/web/src/x"])

    def test_cite_prefix_forms(self):
        rows = [("dot-slash", "See ./code/billing/pay.py", True),
                ("markdown link", "[l](../../code/billing/pay.py)", True),
                ("longer path before it", "See old/code/billing/pay.py", False),
                ("word before it", "See xcode/billing/pay.py", False)]
        for name, text, want in rows:
            with self.subTest(name):
                self.fresh()
                m = self.run_prepare({"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
                                     {"a.md": text + "\n"}, budget=150)
                self.assertEqual(sorted(self.kept(m)), ["code/billing"] if want else [])

    def test_stray_dot_in_a_reference_does_not_cover_the_root_directory_unit(self):
        m = self.run_prepare({"top.py": PAD, "code/billing/pay.py": PAD},
                             {"a.md": "The end . Done.\n"}, budget=150)
        self.assertEqual(m["units"], [])

    def test_covers_directory_above_in_a_nested_repo_needs_a_slash(self):
        code = {"code/backend/apps/x/a/m.py": PAD, "code/backend/apps/x/b/n.py": PAD}
        for item, want in (("apps/x", ["code/backend/apps/x/a", "code/backend/apps/x/b"]),
                           ("apps", [])):
            with self.subTest(item):
                self.fresh()
                m = self.run_prepare(code, {"a.md": f'---\ncovers: "frontend: {item}"\n---\nBody.\n'},
                                     budget=150, repos=["code/backend"])
                self.assertEqual(sorted(self.kept(m)), want)

    def test_header_naming_a_directory_above_covers_units_below(self):
        for item in ("code", "code/"):
            with self.subTest(item):
                self.fresh()
                m = self.run_prepare(
                    {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
                    {"a.md": f'---\ncovers: "modules: {item}"\n---\nBody.\n'}, budget=150)
                self.assertEqual(sorted(self.kept(m)), ["code/auth", "code/billing"])

    def test_header_directory_is_not_a_string_prefix(self):
        m = self.run_prepare({"code/apps/a.py": PAD, "code/other/b.py": PAD},
                             {"a.md": '---\ncovers: "m: code/app"\n---\nBody.\n'}, budget=150)
        self.assertEqual(m["units"], [])

    def test_malformed_profile_record_is_reported_on_stderr(self):
        profile = "```census\naxis: apps\nlabel: no command here\n```\n"
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            self.run_prepare({"code/billing/pay.py": PAD}, {"00-profile.md": profile})
        self.assertIn("incomplete axis record", err.getvalue())

    def test_work_dir_that_is_the_root_or_holds_tracked_files_is_refused(self):
        for name, rel in (("project root", ""), ("tracked directory", "code/billing")):
            with self.subTest(name):
                self.fresh()
                with self.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(io.StringIO()):
                    self.run_prepare({"code/billing/pay.py": PAD}, {"r.md": "code/billing/pay.py\n"},
                                     work=os.path.join(self.root, rel))
                self.assertEqual(cm.exception.code, 2)
                self.assertEqual(os.listdir(os.path.join(self.root, "code/billing")), ["pay.py"])

    def test_covers_line_outside_front_matter_and_root_index_and_profile_do_not_cover(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"a.md": "covers: code\nNot in front matter.\n",
             "00-index.md": "code/billing/pay.py and code/auth/login.py\n",
             "00-profile.md": "code/billing/pay.py\n"}, budget=150)
        self.assertEqual(m["units"], [])

    def test_topic_index_file_is_a_real_reference(self):
        m = self.run_prepare(
            {"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
            {"topic/00-index.md": "Billing is in code/billing/pay.py.\n"}, budget=150)
        self.assertEqual(self.kept(m)["code/billing"]["references"],
                         [".context/references/topic/00-index.md"])

    def test_slug_collision_between_kept_units_aborts(self):
        code = {"code/a-b/x.py": PAD, "code/a/b/y.py": PAD, "code/a/c/z.py": PAD}
        refs = {"r.md": "code/a-b/x.py code/a/b/y.py\n"}
        with self.assertRaises(SystemExit) as cm:
            self.run_prepare(code, refs, budget=150)
        self.assertIn("slug collision", str(cm.exception))
        self.assertFalse(os.path.exists(self.work))  # nothing written

    def test_collision_exit_removes_the_old_manifest(self):
        write(self.work, "manifest.json", "old")
        with self.assertRaises(SystemExit):
            self.run_prepare({"code/a-b/x.py": PAD, "code/a/b/y.py": PAD, "code/a/c/z.py": PAD},
                             {"r.md": "code/a-b/x.py code/a/b/y.py\n"}, budget=150)
        self.assertFalse(os.path.exists(os.path.join(self.work, "manifest.json")))

    def test_uncovered_slug_collision_is_ignored(self):
        code = {"code/a-b/x.py": PAD, "code/a/b/y.py": PAD, "code/a/c/z.py": PAD}
        m = self.run_prepare(code, {"r.md": "code/a-b/x.py\n"}, budget=150)
        self.assertEqual(list(self.kept(m)), ["code/a-b"])

    def test_unit_files_stay_within_budget_and_oversize_file_is_dropped(self):
        code = {f"code/big/f{i}.py": PAD for i in range(4)}
        code["code/big/huge.py"] = "x = 1\n" * 400  # about 600 tokens, over budget
        refs = {"r.md": " ".join(f"code/big/f{i}.py" for i in range(4)) + " code/big/huge.py\n"}
        m = self.run_prepare(code, refs, budget=250)
        self.assertTrue(m["units"])
        for u in m["units"]:
            self.assertLessEqual(u["tokens_est"], 250)
        files = [f for u in m["units"] for f in u["files"]]
        self.assertEqual(sorted(files), [f"code/big/f{i}.py" for i in range(4)])
        manifest = json.loads(pathlib.Path(self.work, "manifest.json").read_text())
        self.assertEqual(manifest["units"], m["units"])
        self.assertEqual(manifest["skipped"], [{"unit": "code/big/huge.py", "reason": "oversize",
                                                "references": [".context/references/r.md"]}])

    def test_covered_data_like_unit_is_listed_as_skipped(self):
        m = self.run_prepare({"code/data/rows.json": PAD, "code/other/a.py": PAD},
                             {"r.md": "Rows are in code/data/rows.json.\n"}, budget=250)
        self.assertEqual(m["units"], [])
        self.assertEqual(m["skipped"], [{"unit": "code/data/rows.json", "reason": "data-like",
                                         "references": [".context/references/r.md"]}])

    def test_previous_run_output_is_replaced(self):
        write(self.work, "units/stale.txt", "old\n")
        write(self.work, "manifest.json", "old")
        m = self.run_prepare({"code/billing/pay.py": PAD, "code/auth/login.py": PAD},
                             {"r.md": "code/billing/pay.py\n"}, budget=150)
        self.assertEqual(sorted(os.listdir(self.work + "/units")), ["code-billing.txt"])
        self.assertEqual(json.loads(pathlib.Path(self.work, "manifest.json").read_text())["units"], m["units"])


if __name__ == "__main__":
    unittest.main()
