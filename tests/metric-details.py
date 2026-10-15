#!/usr/bin/env python3
import importlib.util
import io
from pathlib import Path
import tempfile
import sys
import subprocess
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("metric_details", ROOT / "bars/widgets/ruixen.notch/metric-details.py")
details = importlib.util.module_from_spec(spec)
spec.loader.exec_module(details)


def rss_fields(pages):
    fields = ["0"] * 22
    fields[21] = str(pages)
    return fields


def filesystem(total, free, available):
    return SimpleNamespace(f_frsize=1, f_bsize=1, f_blocks=total, f_bfree=free, f_bavail=available)


class DetailsTests(unittest.TestCase):
    def test_mount_reader_streams_a_bounded_number_of_lines(self):
        class MountStream(io.StringIO):
            def read(self, *args):
                raise AssertionError("Mount input must not be buffered whole")
            def readlines(self, *args):
                raise AssertionError("Mount input must not be buffered whole")
        fixture = MountStream("/dev/a / ext4 rw 0 0\n" * 200)
        with patch.object(details.Path, "open", return_value=fixture):
            self.assertEqual(len(list(details.mount_lines())), 128)

    def test_process_reader_preserves_parentheses_and_skips_short_stats(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "42").mkdir()
            (root / "42/stat").write_text("42 (worker (nested) process) " + " ".join(rss_fields(8)))
            (root / "99").mkdir()
            (root / "99/stat").write_text("99 (short) S 1")
            with patch.object(details, "Path", side_effect=lambda value: root if value == "/proc" else Path(value)):
                entries = list(details.process_stats())
            self.assertEqual(len(entries), 1)
            self.assertEqual(entries[0][1], "worker (nested) process")

    def test_memory_ranks_resident_pages_and_ignores_invalid_counts(self):
        fixture = [("1", "small", rss_fields(1)), ("2", "large", rss_fields(5)),
                   ("3", "invalid", rss_fields("invalid")), ("4", "negative", rss_fields(-1))]
        with patch.object(details, "process_stats", return_value=iter(fixture)), patch.object(details.os, "sysconf", return_value=4096):
            rows = details.memory_processes(4096 * 10)
        self.assertEqual([row["label"] for row in rows], ["large · PID 2", "small · PID 1"])
        self.assertEqual(rows[0]["fraction"], .5)

    def test_gpu_second_sample_reuses_descriptors_but_rejects_replaced_clients(self):
        with tempfile.TemporaryDirectory() as directory:
            info = Path(directory) / "fdinfo"
            text = "drm-driver: amdgpu\ndrm-client-id: 9\ndrm-pdev: pci0\ndrm-engine-gfx: 100 ns\n"
            info.write_text(text)
            identity = ("pci0", "9")
            previous = {identity: {"pid": "42", "name": "worker", "fdinfo": str(info), "sampledAt": 1}}
            with patch.object(details.os, "scandir", side_effect=AssertionError("Must not rediscover descriptors")):
                second = details.gpu_snapshot(previous)
            self.assertEqual(second[identity]["engines"]["gfx"], 100)
            info.write_text(text.replace("id: 9", "id: 10"))
            self.assertEqual(details.gpu_snapshot(previous), {})
            info.unlink()
            self.assertEqual(details.gpu_snapshot(previous), {})

    def test_storage_skips_inaccessible_mount_and_uses_block_size_fallback(self):
        fixture = "/dev/a /gone ext4 rw 0 0\n/dev/a /ok ext4 rw 0 0\n"
        stat = filesystem(100, 80, 10)
        stat.f_frsize = 0
        stat.f_bsize = 4096
        with patch.object(details, "mount_lines", return_value=iter(fixture.splitlines())), patch.object(details.os, "statvfs", side_effect=[OSError(), stat]):
            rows = details.collect("storage")["rows"]
        self.assertEqual(len(rows), 3)
        self.assertEqual(rows[0]["value"], "20.0% capacity used")
        self.assertEqual(rows[1]["value"], "80.0 KiB / 400.0 KiB")

    def test_cli_accepts_only_known_kinds_and_has_help(self):
        script = ROOT / "bars/widgets/ruixen.notch/metric-details.py"
        for args, code in [([], 2), (["wrong"], 2), (["cpu", "extra"], 2), (["--help"], 0)]:
            result = subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)
            self.assertEqual(result.returncode, code)
            self.assertIn("Usage:", result.stdout + result.stderr)

    def test_missing_or_invalid_available_ram_does_not_report_fake_usage(self):
        from unittest.mock import Mock
        for fixture in ["MemTotal: 1024 kB\n", "MemTotal: 1024 kB\nMemAvailable: 2048 kB\n"]:
            with self.subTest(fixture=fixture), patch.object(details, "Path", return_value=Mock(read_text=lambda: fixture)):
                with self.assertRaises(ValueError):
                    details.collect("memory")

    def test_gpu_without_engine_counters_remains_unreported(self):
        client = {"pid": "42", "name": "app", "engines": {}, "capacities": {}, "memory": {"vram": 1024}}
        row = details.rank_gpu({}, {("pci0", "1"): client}, elapsed=.4)[0]
        self.assertIsNone(row["fraction"])
        self.assertEqual(row["value"], "Engine usage unreported")

    def test_gpu_counter_reset_cannot_produce_negative_usage(self):
        identity = ("pci0", "1")
        first = {"pid": "42", "name": "app", "engines": {"gfx": 900}, "capacities": {}, "memory": {}}
        second = dict(first, engines={"gfx": 10})
        row = details.rank_gpu({identity: first}, {identity: second}, elapsed=.4)[0]
        self.assertEqual(row["fraction"], 0)

    def test_command_bounds_output_during_read(self):
        with self.assertRaises(ValueError):
            details.command([sys.executable, "-c", "import sys; sys.stdout.write('x' * (2 * 1024 * 1024))"])

    def test_command_reports_nonzero_exit(self):
        with self.assertRaises(subprocess.CalledProcessError):
            details.command([sys.executable, "-c", "raise SystemExit(2)"])

    def test_command_times_out_and_reaps_worker(self):
        with self.assertRaises(subprocess.TimeoutExpired):
            details.command([sys.executable, "-c", "import time; time.sleep(30)"])

    def test_gpu_uses_each_clients_counter_interval(self):
        identity = ("pci0", "1")
        first = {"pid": "42", "name": "app", "engines": {"gfx": 0}, "capacities": {}, "memory": {}, "sampledAt": 10}
        second = dict(first, engines={"gfx": 500000000}, sampledAt=12)
        row = details.rank_gpu({identity: first}, {identity: second}, elapsed=.4)[0]
        self.assertEqual(row["fraction"], .25)

    def test_memory_summary_uses_available_and_rows_use_physical_total(self):
        fixture = "MemTotal: 1024 kB\nMemAvailable: 512 kB\nCached: 128 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\n"
        from unittest.mock import Mock
        with patch.object(details, "Path", return_value=Mock(read_text=lambda: fixture)), patch.object(details, "process_stats", return_value=iter([("42", "worker", rss_fields(64))])), patch.object(details.os, "sysconf", return_value=4096):
            result = details.collect("memory")
        self.assertEqual(result["summaries"][0]["fraction"], .5)
        self.assertEqual(result["rows"][0]["fraction"], .25)

    def test_storage_percentage_uses_total_not_df_reserved_space_percent(self):
        with patch.object(details, "mount_lines", return_value=iter(["/dev/a / ext4 rw 0 0"])), patch.object(details.os, "statvfs", return_value=filesystem(100, 80, 20)):
            result = details.collect("storage")
        self.assertEqual(result["rows"][0]["value"], "20.0% capacity used")

    def test_gpu_duplicate_file_descriptors_do_not_double_count_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            proc = root / "42"
            (proc / "fd").mkdir(parents=True)
            (proc / "fdinfo").mkdir()
            (proc / "comm").write_text("worker")
            for fd in ["1", "2"]:
                (proc / "fd" / fd).symlink_to("/dev/dri/renderD128")
                (proc / "fdinfo" / fd).write_text("drm-driver: amdgpu\ndrm-client-id: 9\ndrm-pdev: pci0\ndrm-resident-vram: 4 MiB\n")
            with patch.object(details, "Path", side_effect=lambda path: root if path == "/proc" else Path(path)):
                snapshot = details.gpu_snapshot()
            self.assertEqual(len(snapshot), 1)
            self.assertEqual(next(iter(snapshot.values()))["memory"]["vram"], 4 * 1024 * 1024)

    def test_cpu_processes_use_same_total_tick_denominator_as_summary(self):
        rows = details.rank_cpu({("42", "1"): ("worker", 100)}, {("42", "1"): ("worker", 300)}, elapsed=.8, cores=4, ticks=100, capacity_ticks=1000)
        self.assertEqual(rows[0]["fraction"], .2)
        self.assertIn("0.80 cores", rows[0]["detail"])

    def test_cpu_breakdown_explains_unattributed_and_other_processes(self):
        before = (1000, 500, {(str(i), "1"): ("worker", 0) for i in range(12)})
        after = (2000, 1100, {(str(i), "1"): ("worker", 10) for i in range(12)})
        with patch.object(details, "cpu_snapshot", side_effect=[before, after]), patch.object(details.time, "sleep"), patch.object(details.os, "getloadavg", return_value=(0,0,0)):
            result = details.collect("cpu")
        parts = result["summaries"][0]["breakdown"]
        self.assertAlmostEqual(parts["listed"], .1)
        self.assertAlmostEqual(parts["other"], .02)
        self.assertAlmostEqual(parts["unattributed"], .28)
        self.assertAlmostEqual(sum(parts.values()), result["summaries"][0]["fraction"])

    def test_cpu_uses_current_sample_and_total_capacity(self):
        before = {("42", "100"): ("worker", 100), ("99", "200"): ("old", 1000)}
        after = {("42", "100"): ("worker", 300), ("99", "201"): ("new", 5000)}
        rows = details.rank_cpu(before, after, elapsed=1, cores=4, ticks=100)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["fraction"], .5)
        self.assertIn("2.00 cores", rows[0]["detail"])

    def test_memory_bar_uses_physical_ram_capacity(self):
        with patch.object(details, "process_stats", return_value=iter([("123", "worker", rss_fields(256))])), patch.object(details.os, "sysconf", return_value=4096):
            row = details.memory_processes(4 * 1024 * 1024)[0]
        self.assertEqual(row["fraction"], .25)
        self.assertIn("25.0% of RAM", row["value"])

    def test_gpu_uses_busiest_engine_not_sum_of_parallel_engines(self):
        identity = ("0000:04:00.0", "10")
        first = {"pid": "42", "name": "app", "engines": {"gfx": 0, "compute": 0}, "capacities": {}, "memory": {"vram": 1024}}
        second = dict(first, engines={"gfx": 500000000, "compute": 900000000})
        row = details.rank_gpu({identity: first}, {identity: second}, elapsed=1)[0]
        self.assertEqual(row["fraction"], .9)
        self.assertIn("90.0% busiest engine", row["value"])

    def test_gpu_engine_capacity_and_resident_alias(self):
        parsed = details.drm_fields("drm-driver: amdgpu\ndrm-client-id: 2\ndrm-pdev: pci0\ndrm-engine-gfx: 100 ns\ndrm-engine-capacity-gfx: 2\ndrm-resident-vram: 4 MiB\ndrm-memory-vram: 4096 KiB\n")
        self.assertEqual(parsed[3]["vram"], 4 * 1024 * 1024)
        self.assertEqual(parsed[2]["gfx"], 2)

    def test_process_names_with_spaces_and_limit(self):
        fixture = [(str(i), "worker process", rss_fields(256)) for i in range(12)]
        with patch.object(details, "process_stats", return_value=iter(fixture)), patch.object(details.os, "sysconf", return_value=4096):
            rows = details.memory_processes(4 * 1024 * 1024)
        self.assertEqual(len(rows), 10)
        self.assertEqual(rows[0]["label"], "worker process · PID 0")
        self.assertIn("1.0 MiB", rows[0]["value"])

    def test_storage_deduplicates_devices_and_preserves_mount_spaces(self):
        fixture = "/dev/a / ext4 rw 0 0\n/dev/a /home ext4 rw 0 0\n/dev/b /media/My\\040Disk ext4 rw 0 0\ntmpfs /run tmpfs rw 0 0\n"
        with patch.object(details, "mount_lines", return_value=iter(fixture.splitlines())), patch.object(details.os, "statvfs", return_value=filesystem(10240, 8192, 8192)):
            rows = details.collect("storage")["rows"]
        self.assertEqual(len(rows), 6)
        self.assertEqual(rows[3]["label"], "/media/My Disk · /dev/b")

    def test_network_keeps_multiple_addresses(self):
        fixture = '[{"ifname":"test0","operstate":"UP","addr_info":[{"family":"inet","local":"192.0.2.1","prefixlen":24},{"family":"inet6","local":"2001:db8::1","prefixlen":64}]}]'
        with patch.object(details, "command", side_effect=["[]", fixture]):
            rows = details.collect("network")["rows"]
        self.assertEqual(rows[-1]["value"], "2001:db8::1/64")

    def test_gpu_ignores_connectors_and_reports_missing_sensor(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            device = root / "card1/device"
            device.mkdir(parents=True)
            (device / "gpu_busy_percent").write_text("42")
            (root / "card1-DP-1/device").mkdir(parents=True)
            with patch.object(details, "Path", side_effect=lambda path: root if path == "/sys/class/drm" else Path(path)), patch.object(details, "gpu_snapshot", return_value={}):
                rows = details.collect("gpu")["rows"]
            self.assertFalse(any("DP-1" in row["label"] for row in rows))
            self.assertEqual(rows[1]["value"], "42%")
            self.assertEqual(rows[2]["value"], "Not exposed by this driver")


if __name__ == "__main__":
    unittest.main()
