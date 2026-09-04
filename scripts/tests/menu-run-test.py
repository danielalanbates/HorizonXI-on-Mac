#!/usr/bin/env python3
import argparse
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).parents[1] / "harness/menu-run.py"
SPEC = importlib.util.spec_from_file_location("menu_run", SCRIPT)
menu_run = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(menu_run)


class MenuRunTests(unittest.TestCase):
    def test_override_accepts_only_diagnostic_variables(self):
        self.assertEqual(menu_run.parse_override("X87_STOCK_HASH_LIST=abc,def"),
                         ("X87_STOCK_HASH_LIST", "abc,def"))
        self.assertEqual(menu_run.parse_override("DXVK_LOG_LEVEL="), ("DXVK_LOG_LEVEL", ""))
        for bad in ("PATH=/tmp", "X87_PROFILE", "wineprefix=x", "LD_PRELOAD=evil"):
            with self.assertRaises(argparse.ArgumentTypeError):
                menu_run.parse_override(bad)

    def test_process_rows_never_include_arguments(self):
        rows = menu_run.process_rows()
        me = next(command for pid, command in rows if pid == os.getpid())
        self.assertNotIn(" ", me.strip().split("/")[-1])
        self.assertNotIn("--", me)

    def test_related_matching_uses_comm_suffixes_only(self):
        self.assertTrue(any(s.endswith("horizon-loader.exe") for s in menu_run.GAME_SUFFIXES))
        self.assertTrue(set(menu_run.GAME_SUFFIXES) <= set(menu_run.RELATED_SUFFIXES))
        self.assertTrue(set(menu_run.SIDECAR_SUFFIXES) <= set(menu_run.RELATED_SUFFIXES))
        self.assertFalse(set(menu_run.SIDECAR_SUFFIXES) & set(menu_run.GAME_SUFFIXES),
                         "sidecars must not be terminated in phase 1")

    def test_block_profile_completeness(self):
        with tempfile.TemporaryDirectory() as directory:
            cut = Path(directory) / "cut.prof"
            cut.write_bytes(b"x87b" + b"\0" * 100)
            done = Path(directory) / "done.prof"
            done.write_bytes(b"x87b" + b"\0" * 100 + b"CNT0" + b"\0" * 8)
            self.assertFalse(menu_run.block_profile_complete(cut))
            self.assertTrue(menu_run.block_profile_complete(done))
            self.assertFalse(menu_run.block_profile_complete(Path(directory) / "missing"))

    def test_second_return_is_impossible(self):
        for max_returns, characters in ((1, False), (2, True)):
            args = argparse.Namespace(game_dir=Path("/"), env=[], x87_profile=False, limit=1,
                                      max_returns=max_returns, characters=characters)
            runner = menu_run.MenuRun(args)
            runner.returns_sent = max_returns
            with self.assertRaises(RuntimeError):
                runner.send_one_return()

    def test_session_placeholder_expands_to_a_wine_path(self):
        args = argparse.Namespace(game_dir=Path("/"), env=[("DXVK_LOG_PATH", "{session}\\x")],
                                  x87_profile=False, limit=1, max_returns=1, characters=False)
        runner = menu_run.MenuRun(args)
        runner.session_dir = Path("/Users/me/Games/FFXI/logs/performance-captures/s1")
        self.assertEqual(runner.wine_session_path(),
                         "Z:\\Users\\me\\Games\\FFXI\\logs\\performance-captures\\s1")

    def test_cleanup_leaves_a_game_it_did_not_launch_alone(self):
        args = argparse.Namespace(game_dir=Path("/"), env=[], x87_profile=False, limit=1,
                                  max_returns=1, characters=False, sidecar_grace=0.5)
        runner = menu_run.MenuRun(args)
        runner.game_pid = 999999
        killed = []
        original_matching = menu_run.matching
        original_send = menu_run.send_signal
        menu_run.matching = lambda suffixes: (
            [(424242, "horizon-loader.exe")] if suffixes == menu_run.GAME_SUFFIXES
            else [(424242, "horizon-loader.exe"), (424243, "wineserver")])
        menu_run.send_signal = lambda pids, signum: killed.extend(pids)
        try:
            runner.cleanup()
        finally:
            menu_run.matching = original_matching
            menu_run.send_signal = original_send
        self.assertEqual(killed, [])
        self.assertTrue(any("cleanup skipped" in e["label"] for e in runner.record["events"]))

    def test_guarded_variables_cover_every_documented_experiment(self):
        for name in ("X87_PROFILE", "X87_SAMPLE", "X87_ENABLE_FMA_CONTRACT",
                     "FFXI_ON_MAC_DISABLE_X87", "X87_STOCK_HASH_LIST", "X87_DISABLE_X87_IR"):
            self.assertIn(name, menu_run.GUARDED_VARIABLES)


if __name__ == "__main__":
    unittest.main()
