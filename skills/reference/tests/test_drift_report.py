"""Tests for drift/report.py. Layer: unit on synthetic results, transcripts and a stubbed register-item.sh
(the contracts are the grouping, the never-clean skipped list, the per-message-id cost dedupe and the --file calls)."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "drift"))
import report  # noqa: E402


def finding(ref=".context/references/a.md", line=3, typ="stale", unit="u1", detail="says X", ev="a.py:9"):
    return dict(type=typ, reference=ref, reference_line=line, detail=detail, evidence=ev, unit=unit)


def result(findings=(), units=None, verify=True, root="/p"):
    units = units if units is not None else [
        dict(slug="u1", status="ok", failed_stage=None, facts_extracted=2, facts_confirmed=1, findings=len(findings))]
    return dict(run=dict(root=root, work="/w", date="d", verify=verify), units=units, findings=list(findings))


MANIFEST = dict(project="p", skipped=[], units=[
    dict(slug="u1", references=[".context/references/a.md", ".context/references/b.md"]), dict(slug="u2", references=[".context/references/b.md"])])


class Render(unittest.TestCase):
    def test_findings_grouped_by_reference_sorted_by_line_with_all_columns(self):
        out = report.render(result([finding(".context/references/b.md", 1, "wrong", "u2", "b detail", "b.py:1"),
                                    finding(".context/references/a.md", 9, "missing", "u1", "late", "a.py:2"),
                                    finding(".context/references/a.md", 2, "stale", "u1", "early", "a.py:1")]), MANIFEST)
        self.assertIn("\n### .context/references/a.md\n", out)
        self.assertLess(out.index("\n### .context/references/a.md\n"), out.index("\n### .context/references/b.md\n"))
        self.assertLess(out.index("| stale | 2 | early | a.py:1 | u1 |"), out.index("| missing | 9 | late | a.py:2 | u1 |"))
        self.assertIn("| wrong | 1 | b detail | b.py:1 | u2 |", out)

    def test_pipe_and_newline_in_detail_do_not_break_the_row(self):
        out = report.render(result([finding(detail="a | b\nc")]), MANIFEST)
        self.assertIn("| a \\| b c |", out)

    def test_failed_units_are_listed_by_stage(self):
        units = [dict(slug="ok1", status="ok", failed_stage=None, facts_extracted=0, facts_confirmed=0, findings=0),
                 dict(slug="x", status="failed", failed_stage="extract", facts_extracted=0, facts_confirmed=0, findings=0),
                 dict(slug="y", status="failed", failed_stage="compare", facts_extracted=1, facts_confirmed=1, findings=0)]
        out = report.render(result(units=units), MANIFEST)
        self.assertIn("Units: 1 ok, 2 failed (compare: y; extract: x).", out)

    def test_skipped_units_are_listed_so_a_clean_report_is_not_clean(self):
        m = dict(MANIFEST, skipped=[dict(unit="big", reason="oversize", references=[".context/references/a.md", ".context/references/b.md"])])
        out = report.render(result(), m)
        self.assertIn("No findings in the units that completed.", out)
        self.assertIn("| big | oversize | .context/references/a.md, .context/references/b.md |", out)

    def test_finding_outside_the_units_references_or_without_file_line_is_rejected_with_reason(self):
        good = finding(".context/references/a.md", 2, detail="kept")
        foreign = finding(".context/references/zzz.md", 1, detail="comparer was never given this")
        noline = finding(".context/references/a.md", 5, detail="no line", ev="a.py")
        ghost = finding(unit="nope", detail="unit missing")
        acc, rej = report.split_findings([good, foreign, noline, ghost], MANIFEST)
        self.assertEqual(acc, [good])
        self.assertEqual([r["why"] for r in rej], ["reference is not one of this unit's references",
                                                     "evidence is not file:line", "unit not in manifest"])
        out = report.render(result([good, foreign, noline, ghost]), MANIFEST)
        self.assertIn("## Rejected (3)", out)
        self.assertNotIn("| 1 | comparer", out)
        self.assertIn("| .context/references/zzz.md | 1 | a.py:9 | u1 | reference is not one of this unit's references |", out)
        self.assertIn("## Findings (1)", out)

    def test_reference_spellings_are_normalised_before_membership(self):
        m = dict(project="p", skipped=[], units=[dict(slug="u1", references=[".context/references/a.md"])])
        spellings = ["/p/.context/references/a.md", "./.context/references/a.md",
                     ".context/references/a.md (Overview)", ".context/references/a.md",
                     "a.md"]  # the comparer dropped the .context/references/ prefix
        acc, rej = report.split_findings([finding(s) for s in spellings]
                                         + [finding(".context/references/zzz.md"), finding("HIDDEN")], m, "/p")
        self.assertEqual([f["reference"] for f in acc], [".context/references/a.md"] * 5)
        self.assertEqual([f["reference"] for f in rej], [".context/references/zzz.md", "HIDDEN"])

    def test_reference_path_is_not_cut_at_a_md_inside_a_directory_name(self):
        # reference-c11: the lazy match stopped at the first `.md`, so the finding was rejected
        ref = ".context/references/v1.md-notes/a.md"
        m = dict(project="p", skipped=[], units=[dict(slug="u1", references=[ref])])
        self.assertEqual(report.normal_reference(ref, "/p"), ref)
        self.assertEqual(report.normal_reference(ref + " (Overview)", "/p"), ref)
        acc, _ = report.split_findings([finding(ref)], m, "/p")
        self.assertEqual(len(acc), 1)

    def test_manifest_units_with_no_result_are_listed(self):
        # reference-c16/c17: after a split launch the unlaunched covered units must not vanish from the report
        out = report.render(result(), MANIFEST)
        self.assertIn("Units in the manifest with no result (1): u2.", out)
        both = [dict(slug=s, status="ok", failed_stage=None, facts_extracted=0, facts_confirmed=0, findings=0)
                for s in ("u1", "u2")]
        self.assertNotIn("with no result", report.render(result(units=both), MANIFEST))

    def test_facts_past_the_verify_cap_are_reported(self):
        # reference-c19: the workflow caps verify at 50 facts; the unchecked rest must reach the report
        units = [dict(slug="u1", status="ok", failed_stage=None, facts_extracted=51, facts_confirmed=50,
                      facts_unverified=1, findings=0)]
        self.assertIn("Facts past the verify cap and never checked: 1 in 1 unit(s): u1.", report.render(result(units=units), MANIFEST))

    def test_evidence_must_be_a_code_file_line(self):
        for ev, ok in [("x.py:12", True), ("x.py:12-20", True), ("x.py:L12", True), ("src/a/x.ts:3", True),
                       ("12:30 meeting", False), ("see .context/references/a.md:3", False), ("x.py", False),
                       # BL-743: sentence punctuation after a cite, and an absence claim with its empty search
                       ("src/a/x.ts:210-222. Then more.", True),
                       ("Glob backend/apps/x/commands/*.py returns only __init__.py", True),
                       ("grep 'run_job' in backend/apps/x returned no matches", True),
                       ("Glob returned no files", False),
                       ("the file backend/apps/x/a.py is gone", False),
                       ("grep of .context/references/a.md found nothing", False),
                       # reference-c04: evidence wrapped in backticks or quotes
                       ("`src/a/x.ts:12`", True), ("'x.py:12-20'", True), ('"x.py:L12"', True),
                       ("see `src/a/x.ts:12`, then `y.py:3`", True),
                       # reference-c04 (Q17): a short list of extensionless names, exact, also under a path
                       ("Makefile:12", True), ("`Dockerfile:3`", True), ("docker/Dockerfile:3", True),
                       ("./Justfile:3-5", True), ("build/ci/Makefile:L7", True),
                       ("Rakefile:3", False), ("MyDockerfile:3", False),
                       ("README:3", False), ("Makefile", False)]:
            with self.subTest(ev):
                acc, _ = report.split_findings([finding(ev=ev)], MANIFEST, "/p")
                self.assertEqual(len(acc), 1 if ok else 0)

    def test_verify_off_counts_are_shown(self):
        units = [dict(slug="u1", status="ok", failed_stage=None, facts_extracted=5, facts_confirmed=None,
                      facts_dropped_inferred=2, facts_to_compare=3, not_covered=0, findings=0)]
        out = report.render(result(units=units, verify=False), MANIFEST)
        self.assertIn("Inferred facts dropped: 2. Facts given to compare: 3.", out)

    def test_unread_files_are_reported(self):
        units = [dict(slug="u1", status="ok", failed_stage=None, facts_extracted=1, facts_confirmed=1,
                      not_covered=2, findings=0)]
        self.assertIn("Files the extractor did not read: 2 in 1 unit(s): u1.", report.render(result(units=units), MANIFEST))

    def test_cost_absent_without_transcripts(self):
        self.assertIn("Not available", report.render(result(), MANIFEST))


def line(msg_id, model, usage):
    return json.dumps({"message": {"id": msg_id, "role": "assistant", "model": model, "usage": usage}})


class Cost(unittest.TestCase):
    def test_usage_repeated_on_content_block_lines_counts_once_per_message_id(self):
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "journal.jsonl").write_text(
                json.dumps({"type": "started", "agentId": "a1", "label": "compare:u1"}) + "\n")
            use = dict(input_tokens=1_000_000, output_tokens=0)
            pathlib.Path(d, "agent-a1.jsonl").write_text(
                "\n".join([line("m1", "claude-sonnet-5-5", use)] * 3 + ["not json"]) + "\n")
            c = report.cost(d)
        self.assertAlmostEqual(c["stages"]["compare"]["usd"], 2.0)  # 1M input at $2, once, not three times
        self.assertAlmostEqual(c["total"], 2.0)

    def test_haiku_55_over_100k_prompt_uses_the_high_tier_and_stages_split_by_label(self):
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "journal.jsonl").write_text(
                json.dumps({"type": "started", "agentId": "a1", "label": "extract:u1"}) + "\n"
                + json.dumps({"type": "started", "agentId": "a2", "label": "verify:u1"}) + "\n")
            pathlib.Path(d, "agent-a1.jsonl").write_text(
                line("m1", "claude-haiku-5-5", dict(input_tokens=200_000)) + "\n")
            pathlib.Path(d, "agent-a2.jsonl").write_text(
                line("m2", "claude-unknown", dict(input_tokens=5)) + "\n")
            c = report.cost(d)
        self.assertAlmostEqual(c["stages"]["extract"]["usd"], 0.10)  # 200k at $0.50
        self.assertEqual(c["stages"]["extract"]["maxprompt"], 200_000)
        self.assertEqual(c["stages"]["verify"]["unpriced"], 1)
        self.assertIn("| total | 0.10 |", report.render(result(), MANIFEST, c))


class CostMatchesUsageRetro(unittest.TestCase):
    """reference-s11/s12 (Q16): report.cost prices with usage-retro's own helpers, not a drifted copy.
    Layer: unit; the contract is that the same transcript costs the same in both tools."""
    USAGE = dict(
        input_tokens=10, output_tokens=100, cache_read_input_tokens=1_000,
        cache_creation=dict(ephemeral_5m_input_tokens=6976), cache_creation_input_tokens=8480,  # flat total beats stale dict
        iterations=[dict(type="message", input_tokens=10, output_tokens=100),
                    dict(type="advisor_message", model="claude-opus-5-5", input_tokens=50_000, output_tokens=2_000)])

    def write(self, d, model):
        pathlib.Path(d, "journal.jsonl").write_text(json.dumps({"type": "started", "agentId": "a1", "label": "compare:u"}) + "\n")
        pathlib.Path(d, "agent-a1.jsonl").write_text(
            line("m1", model, self.USAGE) + "\n" + line("m2", "<synthetic>", dict(input_tokens=1_000_000)) + "\n")

    def expected(self, d, model):
        sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "audit", "scripts", "usage-retro"))
        import pricing
        import subagent_spend
        total = 0.0
        for m, tk, _ in subagent_spend.turns(os.path.join(d, "agent-a1.jsonl"), set()):
            total += pricing.usd_request(m, tk) or 0
        return total

    def test_total_equals_usage_retro_for_flat_cache_creation_advisor_iteration_and_a_model_the_copy_lacked(self):
        # Literal totals (hand-checked): sonnet-5-5 0.02232 top-level + 0.24 opus advisor; fable-5-1 0.35135.
        for model, literal in (("claude-sonnet-5-5", 0.26232), ("claude-fable-5-1", 0.35135)):
            with self.subTest(model), tempfile.TemporaryDirectory() as d:
                self.write(d, model)
                want = self.expected(d, model)
                self.assertAlmostEqual(want, literal)
                c = report.cost(d)
                self.assertAlmostEqual(c["total"], literal)
                self.assertEqual(c["stages"]["compare"]["unpriced"], 0)  # synthetic placeholder skipped, fable priced

    def test_report_py_runs_from_any_cwd(self):
        with tempfile.TemporaryDirectory() as d:
            self.write(d, "claude-sonnet-5-5")
            pathlib.Path(d, "manifest.json").write_text(json.dumps(MANIFEST))
            pathlib.Path(d, "result.json").write_text(json.dumps(result([finding()])))
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts", "drift", "report.py")
            r = subprocess.run([sys.executable, script, os.path.join(d, "result.json"), d, "--transcripts", d],
                               cwd=d, capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("| total |", r.stdout)


class CostEdges(unittest.TestCase):
    def tdir(self, d, lines):
        pathlib.Path(d, "journal.jsonl").write_text(
            json.dumps({"type": "started", "agentId": "a1", "label": "compare:u"}) + "\n" + '{"type": "sta')  # truncated tail
        pathlib.Path(d, "agent-a1.jsonl").write_text("\n".join(lines) + "\n" + '{"message": {"id"')

    def test_messages_without_an_id_are_each_counted(self):
        with tempfile.TemporaryDirectory() as d:
            use = dict(input_tokens=1_000_000)
            self.tdir(d, [line(None, "claude-sonnet-5-5", use)] * 2)
            self.assertAlmostEqual(report.cost(d)["total"], 4.0)

    def test_cache_creation_with_only_the_1h_key_has_a_zero_5m_part(self):
        with tempfile.TemporaryDirectory() as d:
            use = dict(cache_creation=dict(ephemeral_1h_input_tokens=1_000_000), cache_creation_input_tokens=1_000_000)
            self.tdir(d, [line("m1", "claude-sonnet-5-5", use)])
            self.assertAlmostEqual(report.cost(d)["total"], 4.0)  # 1M at the 1h rate, 5m part 0

    def test_truncated_journal_and_transcript_lines_are_skipped(self):
        with tempfile.TemporaryDirectory() as d:
            self.tdir(d, [line("m1", "claude-sonnet-5-5", dict(input_tokens=1_000_000))])
            self.assertAlmostEqual(report.cost(d)["stages"]["compare"]["usd"], 2.0)


class CostGuards(unittest.TestCase):
    def test_a_journal_start_without_a_label_falls_back_to_the_agent_id(self):
        # reference-c20: d["label"] raised KeyError and killed the report
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "journal.jsonl").write_text(json.dumps({"type": "started", "agentId": "a1"}) + "\n")
            pathlib.Path(d, "agent-a1.jsonl").write_text(line("m1", "claude-sonnet-5-5", dict(input_tokens=1_000_000)) + "\n")
            self.assertAlmostEqual(report.cost(d)["stages"]["a1"]["usd"], 2.0)

    def test_an_unreadable_transcripts_dir_does_not_stop_the_findings(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "manifest.json").write_text(json.dumps(MANIFEST))
            pathlib.Path(d, "result.json").write_text(json.dumps(result([finding()])))
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                report.main([os.path.join(d, "result.json"), d, "--transcripts", os.path.join(d, "nope")])
        self.assertIn("### .context/references/a.md", out.getvalue())
        self.assertIn("Not available", out.getvalue())
        self.assertIn("cost unavailable", err.getvalue())


class Register(unittest.TestCase):
    def test_deferred_and_archived_titles_count_as_already_registered(self):
        # reference-c05: only backlog/*.md was read, so --file re-registered an item that was deferred or closed
        with tempfile.TemporaryDirectory() as d:
            for sub in ("_deferred", "_archive"):
                os.makedirs(os.path.join(d, ".context", "backlog", sub))
            f1, f2 = finding(detail="in deferred"), finding(detail="in archive")
            for sub, f in (("_deferred", f1), ("_archive", f2)):
                t = f"Reference drift ({f['type']}): {f['reference']}:{f['reference_line']} {f['detail']}"
                pathlib.Path(d, ".context", "backlog", sub, "BL-1.md").write_text(f'---\ntitle: "{t}"\n---\n')
            stub = os.path.join(d, "stub.sh")
            pathlib.Path(stub).write_text("#!/usr/bin/env bash\nexit 3\n")
            self.assertEqual(report.register([f1, f2], d, script=stub), (0, 2))

    def test_identical_findings_in_one_run_register_once(self):
        # reference-c06: `have` was built once, so two identical findings each became an item
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "calls.log")
            stub = os.path.join(d, "stub.sh")
            pathlib.Path(stub).write_text(f'#!/usr/bin/env bash\necho x >> "{log}"\n')
            self.assertEqual(report.register([finding(), finding()], d, script=stub), (1, 1))
            self.assertEqual(len(pathlib.Path(log).read_text().splitlines()), 1)

    def test_a_mid_batch_failure_says_how_many_were_registered_first(self):
        # reference-c18: the raise came with no word on the items already written
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            stub = os.path.join(d, "stub.sh")
            flag = os.path.join(d, "flag")
            pathlib.Path(stub).write_text(f'#!/usr/bin/env bash\n[ -e "{flag}" ] && exit 3\ntouch "{flag}"\n')
            err = io.StringIO()
            with contextlib.redirect_stderr(err), self.assertRaises(subprocess.CalledProcessError):
                report.register([finding(detail="one"), finding(detail="two")], d, script=stub)
            self.assertIn("registered 1", err.getvalue())

    def test_already_registered_titles_are_skipped_on_the_second_run(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "calls.log")
            root = os.path.join(d, "proj")
            os.makedirs(os.path.join(root, ".context", "backlog"))
            stub = os.path.join(d, "stub.sh")
            # a faithful stand-in: writes the item the way register-item.sh does (escaped title in front matter)
            pathlib.Path(stub).write_text(
                '#!/usr/bin/env bash\necho x >> "' + log + '"\n'
                'while [ $# -gt 0 ]; do [ "$1" = --title ] && t="$2"; shift; done\n'
                'printf -- \'---\\ntitle: "%s"\\n---\\n\' "$(printf %s "$t" | sed \'s/\\\\/\\\\\\\\/g; s/"/\\\\"/g\')" '
                '> "' + root + '/.context/backlog/BL-$RANDOM.md"\n')
            fs = [finding(detail='says "X" | y'), finding(".context/references/b.md", 4, "wrong", "u2", "d2")]
            self.assertEqual(report.register(fs, root, script=stub), (2, 0))
            self.assertEqual(report.register(fs, root, script=stub), (0, 2))
            self.assertEqual(len(pathlib.Path(log).read_text().splitlines()), 2)

    def test_one_register_call_per_finding_with_origin_and_nothing_else_written(self):
        with tempfile.TemporaryDirectory() as d:
            log = os.path.join(d, "calls.log")
            stub = os.path.join(d, "stub.sh")
            pathlib.Path(stub).write_text(f'#!/usr/bin/env bash\nprintf "%s|" "$@" >> "{log}"\necho >> "{log}"\n')
            root = os.path.join(d, "proj")
            os.makedirs(root)
            report.register([finding(detail="d1"), finding(".context/references/b.md", 4, "wrong", "u2", "d2")], root, script=stub)
            calls = pathlib.Path(log).read_text().splitlines()
            self.assertEqual(len(calls), 2)
            self.assertTrue(all(c.startswith("--origin|manual|--title|") for c in calls))
            self.assertIn(".context/references/b.md:4 d2", calls[1])
            self.assertEqual(sorted(os.listdir(d)), ["calls.log", "proj", "stub.sh"])
            self.assertEqual(os.listdir(root), [])

    def test_a_failing_register_call_stops_the_run(self):
        with tempfile.TemporaryDirectory() as d:
            stub = os.path.join(d, "stub.sh")
            pathlib.Path(stub).write_text("#!/usr/bin/env bash\nexit 3\n")
            with self.assertRaises(Exception):
                report.register([finding()], d, script=stub)


class Main(unittest.TestCase):
    def test_file_mode_registers_only_accepted_findings(self):
        import contextlib
        import io
        calls = []
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "manifest.json").write_text(json.dumps(MANIFEST))
            pathlib.Path(d, "result.json").write_text(json.dumps(
                result([finding(detail="kept"), finding(".context/references/zzz.md", detail="foreign")], root=d)))
            orig = report.register
            report.register = lambda fs, root, script=None: (calls.append((fs, root)), (0, 0))[1]
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    report.main([os.path.join(d, "result.json"), d, "--file"])
            finally:
                report.register = orig
        self.assertEqual([f["detail"] for f in calls[0][0]], ["kept"])

    def test_cli_reads_result_and_manifest_and_prints_markdown(self):
        import contextlib
        import io
        with tempfile.TemporaryDirectory() as d:
            pathlib.Path(d, "manifest.json").write_text(json.dumps(MANIFEST))
            pathlib.Path(d, "result.json").write_text(json.dumps(result([finding()])))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                report.main([os.path.join(d, "result.json"), d])
        self.assertIn("### .context/references/a.md", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
