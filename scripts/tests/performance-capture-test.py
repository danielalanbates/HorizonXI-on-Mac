#!/usr/bin/env python3
import csv
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).parents[1] / "harness/capture-performance.py"
SPEC = importlib.util.spec_from_file_location("performance_capture", SCRIPT)
capture = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(capture)


def x87_profile_record(pid, written, elapsed, leaves, *, window=None, complete=True,
                       profiled=None):
    sample_count = sum(count for _pc, count in leaves)
    profiled = elapsed if profiled is None else profiled
    header = (
        "# x87sidecar guest-pc sample profile\n"
        "version 2\n"
        f"pid {pid}\n"
        f"written {written}\n"
        "rate_hz 1000.0\n"
        "effective_hz 998.0\n"
        f"elapsed_s {elapsed}\n"
        f"profiled_s {profiled}\n"
        f"samples {sample_count}\n"
        f"resolved {sample_count}\n"
        f"in_range {sample_count}\n"
    )
    if window is not None:
        sequence, start, end = window
        header += (f"window_seq {sequence}\nwindow_start_s {start}\n"
                   f"window_end_s {end}\n")
    body = (
        "\n[modules]\n# base size kind state path\n"
        "0x1000 0x1000 pe loaded C:\\game\\horizon-loader.exe\n"
        "0x3000 0x1000 pe loaded C:\\game\\d3d9.dll\n"
        "\n[leaves]\n# tid pc count\n"
        + "".join(f"0x1 0x{pc:x} {count}\n" for pc, count in leaves)
        + "\n[host_leaves]\n# tid pc count reason\n"
        + "\n[host_syscalls]\n# tid pc svc count\n"
        + "\n[stacks]\n# tid root;...;leaf count\n"
    )
    if window is not None and complete:
        body += f"\nend_window {window[0]}\n"
    return header + body


class PerformanceCaptureTests(unittest.TestCase):
    def test_redacts_loader_credentials_and_secret_assignments(self):
        source = (
            "loader --user ronald --pass=correct-horse\n"
            'args: ["--username", "ronald", "--password", "battery"]\n'
            "API_TOKEN=abcdef\n"
        )
        cleaned = capture.redact(source)
        for secret in ("ronald", "correct-horse", "battery", "abcdef"):
            self.assertNotIn(secret, cleaned)
        self.assertGreaterEqual(cleaned.count("[REDACTED]"), 5)

    def test_stable_time_requires_consecutive_samples(self):
        rows = [{"elapsed": second, "fps": fps} for second, fps in enumerate(
            [2, 31, 29, 31, 32, 33, 34, 35, 20]
        )]
        self.assertEqual(capture.stable_time(rows, 30, count=5), 3)
        self.assertIsNone(capture.stable_time(rows, 50, count=2))

    def test_pipeline_compiler_summary_correlates_low_fps_and_growth(self):
        rows = [
            {"fps": 2, "compiler_busy": 4, "graphics_pipelines": 10,
             "compute_pipelines": 1},
            {"fps": 4, "compiler_busy": 2, "graphics_pipelines": 15,
             "compute_pipelines": 1},
            {"fps": 55, "compiler_busy": 0, "graphics_pipelines": 15,
             "compute_pipelines": 1},
        ]
        summary = capture.pipeline_compiler_summary(rows)
        self.assertEqual(summary["samples_compiler_busy"], 2)
        self.assertEqual(summary["samples_pipeline_growing"], 1)
        self.assertEqual(summary["low_fps_samples_compiler_busy"], 2)
        self.assertEqual(summary["low_fps_samples_pipeline_growing"], 1)
        self.assertEqual(summary["fps_median_compiler_busy"], 3)
        self.assertEqual(summary["fps_median_compiler_idle"], 55)

    def test_pipeline_compiler_summary_ignores_older_fps_logs(self):
        self.assertEqual(capture.pipeline_compiler_summary([{"fps": 12}]), {})

    def test_process_rusage_includes_per_process_disk_counters(self):
        usage = capture.proc_rusage(os.getpid())
        self.assertIn("disk_read_bytes", usage)
        self.assertIn("disk_write_bytes", usage)
        self.assertIn("phys_footprint_bytes", usage)

    def test_gpu_stats_keeps_only_numeric_performance_counters(self):
        text = ('  |   "PerformanceStatistics" = {"Device Utilization %"=27,'
                '"Renderer Utilization %"=24,"Tiler Utilization %"=8,'
                '"In use system memory"=1234,"recoveryCount"=2}\n'
                '  |   "model" = "secret-free model name"\n')
        self.assertEqual(capture.parse_gpu_stats(text), {
            "device_utilization_percent": 27,
            "renderer_utilization_percent": 24,
            "tiler_utilization_percent": 8,
            "in_use_system_memory_bytes": 1234,
            "recovery_count": 2,
        })

    def test_stage_summary_preserves_the_longest_named_phase(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "stages.csv"
            path.write_text("elapsed_ms,phase,phase_ms\n1000,acquire_image,900\n"
                            "2000,synchronize_previous_present,1900\n")
            self.assertEqual(capture.stage_summary(path)["longest_phase"],
                             "synchronize_previous_present")

    def test_stage_summary_separates_idle_and_active_phases(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "stages.csv"
            path.write_text("elapsed_ms,phase,phase_ms\n1000,blit,20\n"
                            "2000,outside_present,1900\n")
            summary = capture.stage_summary(path, {"outside_present"})
            self.assertEqual(summary["longest_phase"], "outside_present")
            self.assertEqual(summary["longest_active_phase"], "blit")

    def test_x87_summary_requires_multiple_handshakes_and_live_throughput(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "launcher.log"
            path.write_text(
                "[rosettax87] cooperative service registered: x87sidecar.1\n"
                "[rosettax87] cooperative attach: task=1 thread=2 reply=3\n"
                "[rosettax87] cooperative service registered: x87sidecar.2\n"
                "[rosettax87] cooperative attach: task=4 thread=5 reply=6\n"
                "[rosettax87] sidecar: 32000 req/s (total 64000)\n"
            )
            summary = capture.x87_summary(path)
            self.assertEqual(summary["status"], "active")
            self.assertEqual(summary["cooperative_attaches"], 2)
            self.assertEqual(summary["throughput_max_requests_s"], 32000)

    def test_x87_summary_reports_disabled_and_failed_states(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "launcher.log"
            path.write_text("i  x87 acceleration is off for this world\n")
            self.assertEqual(capture.x87_summary(path)["status"], "disabled")
            path.write_text("[rosettax87] cooperative handshake receive failed: timed out\n")
            self.assertEqual(capture.x87_summary(path)["status"], "handshake_failed")

    def test_guest_pc_profiles_are_pid_scoped_and_correlated_with_fps_windows(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "x87-sample-123.prof").write_text(x87_profile_record(
                123, "1970-01-01T00:17:00Z", 20, [(0x1100, 50), (0x3100, 50)]))
            windows = (
                x87_profile_record(123, "1970-01-01T00:16:50Z", 10,
                                   [(0x1100, 100)], window=(0, 0, 10))
                + x87_profile_record(123, "1970-01-01T00:17:00Z", 10,
                                     [(0x3100, 100)], window=(1, 10, 20))
                # Simulate a process killed halfway through an append. The missing
                # end_window marker must keep this record out of the result.
                + x87_profile_record(123, "1970-01-01T00:17:10Z", 10,
                                     [(0x1100, 100)], window=(2, 20, 30), complete=False)
            )
            (output / "x87-sample-123.prof.windows").write_text(windows)
            (output / "x87-sample-456.prof").write_text(x87_profile_record(
                456, "1970-01-01T00:17:00Z", 20, [(0x1100, 100)]))
            fps = [{"epoch": 1005, "fps": 2}, {"epoch": 1015, "fps": 55}]

            summary = capture.x87_profiles_summary(output, 123, fps)

            self.assertEqual(summary["status"], "captured")
            self.assertEqual(summary["profile_files"], 2)
            self.assertEqual(summary["game_profile"]["window_records"], 2)
            self.assertEqual(summary["game_profile"]["profile"]["coverage_percent"], 100)
            self.assertEqual(summary["game_profile"]["profile"]["coverage_status"], "adequate")
            self.assertEqual(len(summary["windows"]), 2)
            self.assertEqual(summary["windows"][0]["fps"]["classification"], "slow")
            self.assertEqual(summary["windows"][1]["fps"]["classification"], "recovered")
            self.assertEqual(
                summary["phase_hotspots"]["slow"]["top_guest_leaves"][0]["location"],
                "horizon-loader.exe+0x100")
            self.assertEqual(
                summary["phase_hotspots"]["recovered"]["top_guest_leaves"][0]["location"],
                "d3d9.dll+0x100")

    def test_summary_flags_inadequate_guest_coverage_and_skips_empty_hotspots(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "x87-sample-123.prof").write_text(x87_profile_record(
                123, "1970-01-01T00:01:40Z", 100, [], profiled=0.8))
            (output / "x87-sample-123.prof.windows").write_text(x87_profile_record(
                123, "1970-01-01T00:00:10Z", 10, [], window=(0, 0, 10), profiled=0))
            (output / "fps.csv").write_text("epoch,elapsed,fps\n5,5,2\n")

            summary = capture.build_summary(output, 100, 123, "standard")

            profile = summary["guest_pc_profiles"]["game_profile"]["profile"]
            self.assertEqual(profile["coverage_percent"], 0.8)
            self.assertEqual(profile["coverage_status"], "inadequate")
            rendered = (output / "summary.txt").read_text()
            self.assertIn("0.8%, inadequate", rendered)
            self.assertNotIn("Slow-window hotspots:", rendered)

    def test_summary_classifies_idle_renderer_as_game_between_frames(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "present-stages.csv").write_text(
                "elapsed_ms,phase,phase_ms\n1000,blit,1\n4000,outside_present,3000\n")
            (output / "submit-stages.csv").write_text(
                "elapsed_ms,phase,phase_ms\n1000,submit,1\n4000,waiting,2990\n")
            summary = capture.build_summary(output, 4, 123, "standard")
            self.assertEqual(summary["likely_bottleneck"]["classification"],
                             "game_between_frames")
            self.assertNotIn("likely_stall", summary)

    def test_summary_classifies_work_inside_present_as_renderer_stall(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "present-stages.csv").write_text(
                "elapsed_ms,phase,phase_ms\n1000,blit,1\n4000,acquire_image,3000\n")
            (output / "submit-stages.csv").write_text(
                "elapsed_ms,phase,phase_ms\n1000,waiting,1\n")
            summary = capture.build_summary(output, 4, 123, "standard")
            self.assertEqual(summary["likely_bottleneck"]["classification"],
                             "renderer_stall")
            self.assertEqual(summary["likely_bottleneck"]["phase"], "acquire_image")

    def test_summary_classifies_long_draw_up_copy_as_renderer_stall(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            (output / "draw-up-stages.csv").write_text(
                "elapsed_ms,phase,phase_ms,buffer_size\n"
                "1000,copy_vertex,900,112\n4000,copy_vertex,3900,112\n")
            summary = capture.build_summary(output, 4, 123, "standard")
            self.assertEqual(summary["likely_bottleneck"]["classification"],
                             "renderer_stall")
            self.assertEqual(summary["likely_bottleneck"]["lane"], "draw_up")
            self.assertEqual(summary["likely_bottleneck"]["phase"], "copy_vertex")

    def test_thread_snapshot_never_contains_command_text(self):
        release = threading.Event()
        worker = threading.Thread(target=lambda: release.wait(2))
        worker.start()
        rows = capture.thread_snapshot(os.getpid())
        release.set()
        worker.join()
        self.assertTrue(rows)
        allowed = {"index", "cpu_percent", "state", "system_s", "user_s"}
        self.assertTrue(all(set(row) == allowed for row in rows))

    def test_task_info_reports_kernel_counters_without_command_text(self):
        info = capture.proc_task_info(os.getpid())
        self.assertGreater(info["faults"], 0)
        self.assertGreater(info["syscalls_unix"], 0)
        self.assertGreaterEqual(info["threads"], 1)
        self.assertTrue(all(isinstance(value, int) for value in info.values()))

    def test_timeline_adds_fault_rates_only_when_counters_exist(self):
        fps = [{"epoch": 10.0, "elapsed": 1.0, "fps": 5.0, "draws": 20.0},
               {"epoch": 11.0, "elapsed": 2.0, "fps": 50.0, "draws": 300.0}]
        process = [
            {"epoch": 9.0, "elapsed": 0.0, "cpu_percent": 90.0, "faults": 1000, "cow_faults": 0,
             "syscalls_mach": 10, "syscalls_unix": 10, "context_switches": 5,
             "task_user_ns": 1e8, "task_system_ns": 1e8, "threads": 40},
            {"epoch": 10.0, "elapsed": 1.0, "cpu_percent": 90.0, "faults": 41000, "cow_faults": 0,
             "syscalls_mach": 110, "syscalls_unix": 10, "context_switches": 5,
             "task_user_ns": 2e8, "task_system_ns": 9e8, "threads": 40},
            {"epoch": 11.0, "elapsed": 2.0, "cpu_percent": 60.0, "faults": 42000, "cow_faults": 0,
             "syscalls_mach": 120, "syscalls_unix": 20, "context_switches": 5,
             "task_user_ns": 7e8, "task_system_ns": 9.5e8, "threads": 40},
        ]
        timeline = capture.correlated_timeline(process, fps)
        self.assertEqual(len(timeline), 2)
        self.assertEqual(timeline[0]["faults_s"], 40000)
        self.assertAlmostEqual(timeline[0]["kernel_share"], 8 / 9, places=3)
        self.assertEqual(timeline[1]["faults_s"], 1000)
        phases = capture.stall_phase_summary(timeline)
        self.assertEqual(phases["slow_over_recovered"]["faults_s"], 40.0)
        self.assertIn("page faults dominate", phases["reading"])

        legacy = [{k: v for k, v in row.items() if k in ("epoch", "elapsed", "cpu_percent")}
                  for row in process]
        legacy_timeline = capture.correlated_timeline(legacy, fps)
        self.assertNotIn("faults_s", legacy_timeline[0])
        self.assertEqual(capture.stall_phase_summary(legacy_timeline), {})

    def test_low_fps_windows_group_consecutive_slow_seconds(self):
        rows = [{"elapsed": float(t), "fps": 0.4 if t in (5, 6, 7, 20, 21) else 55.0,
                 "faults_s": 0.0, "kernel_share": 0.0, "cpu_cores": 0.9,
                 "phys_footprint_mb": 600.0 + t, "draws": 300.0} for t in range(30)]
        windows = capture.low_fps_windows(rows)
        self.assertEqual([(w["start_s"], w["end_s"], w["seconds"]) for w in windows],
                         [(5.0, 7.0, 3), (20.0, 21.0, 2)])
        self.assertEqual(windows[0]["footprint_change_mb"], 2.0)

    def test_block_profile_completeness_needs_the_counter_tag(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "x87-block-7.prof").write_bytes(b"x87b" + b"\0" * 4096)
            (root / "x87-block-9.prof").write_bytes(b"x87b" + b"\0" * 4096 + b"CNT0" + b"\0" * 64)
            summary = capture.block_profiles_summary(root, 9)
            self.assertEqual(summary["status"], "complete")
            self.assertEqual([p["role"] for p in summary["profiles"]], ["auxiliary", "game"])
            self.assertIn("incomplete", capture.block_profiles_summary(root, 7)["status"])
            self.assertEqual(capture.block_profiles_summary(root, 8)["status"], "no game profile")
            self.assertEqual(capture.block_profiles_summary(root / "none", 1)["status"], "none")

    def test_export_symbols_name_runtime_leaves_and_callers_blame_game_code(self):
        ucrt = Path.home() / ("Library/Application Support/HorizonXI-on-Mac/runtimes/"
                              "wine-cx-26.3.0-1/wine/lib/wine/i386-windows/ucrtbase.dll")
        if not ucrt.is_file():
            self.skipTest("patched Wine runtime is not installed")
        exports = capture.pe_exports(str(ucrt))
        self.assertTrue(any(name == "memset" for _rva, name in exports))
        memset_rva = next(rva for rva, name in exports if name == "memset")
        self.assertEqual(capture.export_symbol(str(ucrt), memset_rva + 0x2c), "memset+0x2c")
        self.assertIsNone(capture.export_symbol(str(ucrt), 0x10))  # header, no export yet
        self.assertEqual(capture.pe_exports("/nonexistent.dll"), [])

        modules = [
            {"base": 0x400000, "size": 0x100000, "kind": "pe", "path": "C:\\game\\FFXiMain.dll"},
            {"base": 0x7b600000, "size": 0x274000, "kind": "pe", "path": str(ucrt)},
            {"base": 0x78ea0000, "size": 0x341000, "kind": "pe", "path": "C:\\game\\d3d9.dll"},
        ]
        leaf = 0x7b600000 + memset_rva + 0x2c
        record = {
            "header": {"samples": 100}, "modules": modules, "leaves": [],
            "host_leaves": [], "host_syscalls": [{"tid": 1, "pc": 1, "svc": -59, "count": 5}],
            "stacks": [
                {"tid": 1, "pcs": [0x401000, 0x78eb0000, leaf], "count": 60},
                {"tid": 1, "pcs": [0x402000, leaf], "count": 30},
                {"tid": 1, "pcs": [0x78eb0000, leaf], "count": 10},
            ],
        }
        location = capture.module_location(leaf, modules)
        self.assertEqual(location["location"], "ucrtbase.dll!memset+0x2c")
        callers = capture.caller_attribution(record)
        self.assertEqual([c["caller"] for c in callers],
                         ["FFXiMain.dll+0x1000", "FFXiMain.dll+0x2000",
                          "runtime-only (d3d9.dll+0x10000)"])
        self.assertEqual(callers[0]["percent_of_samples"], 60.0)
        self.assertEqual(callers[0]["leaves"][0]["location"], "ucrtbase.dll!memset+0x2c")
        inclusive = {m["module"]: m["percent_of_samples"]
                     for m in capture.inclusive_module_share(record)}
        self.assertEqual(inclusive["ucrtbase.dll"], 100.0)
        self.assertEqual(inclusive["d3d9.dll"], 70.0)
        summary = capture.x87_record_summary(record)
        self.assertEqual(summary["top_host_syscalls"][0]["name"], "swtch_pri")

    def test_summary_prices_cpu_and_disk_and_reads_fps(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            with (output / "fps.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=("epoch", "elapsed", "fps", "draws"))
                writer.writeheader()
                for index, fps in enumerate((2, 5, 30, 31, 32, 33, 34)):
                    writer.writerow({"epoch": 100 + index, "elapsed": index,
                                     "fps": fps, "draws": 400})
            with (output / "process.csv").open("w", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=(
                    "epoch", "cpu_percent", "user_ns", "system_ns", "disk_read_bytes",
                    "disk_write_bytes", "pageins", "phys_footprint_bytes"))
                writer.writeheader()
                writer.writerow({"epoch": 100, "cpu_percent": 50,
                                 "user_ns": 0, "system_ns": 0,
                                 "disk_read_bytes": 0, "disk_write_bytes": 0,
                                 "pageins": 2, "phys_footprint_bytes": 10 * 1024 * 1024})
                writer.writerow({"epoch": 106, "cpu_percent": 50,
                                 "user_ns": 3_000_000_000, "system_ns": 0,
                                 "disk_read_bytes": 6 * 1024 * 1024,
                                 "disk_write_bytes": 3 * 1024 * 1024,
                                 "pageins": 5, "phys_footprint_bytes": 20 * 1024 * 1024})

            summary = capture.build_summary(output, 6, 123, "standard")
            self.assertEqual(summary["fps"]["stable_30_elapsed_s"], 2)
            self.assertEqual(summary["host_process"]["cpu_core_average"], 0.5)
            self.assertEqual(summary["host_process"]["coverage_percent"], 100)
            self.assertEqual(summary["host_process"]["disk_read_mb"], 6)
            self.assertEqual(summary["correlated_phases"]["recovered_at_least_30_fps"]["disk_read_mb_s"], 1)
            self.assertEqual(json.loads((output / "summary.json").read_text())["pid"], 123)


if __name__ == "__main__":
    unittest.main()
