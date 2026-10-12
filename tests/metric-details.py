#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("metric_details", ROOT / "bars/widgets/ruixen.notch/metric-details.py")
details = importlib.util.module_from_spec(spec)
spec.loader.exec_module(details)


class DetailsTests(unittest.TestCase):
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
        with self.assertRaises(details.subprocess.CalledProcessError):
            details.command([sys.executable, "-c", "raise SystemExit(2)"])

    def test_command_times_out_and_reaps_worker(self):
        with self.assertRaises(details.subprocess.TimeoutExpired):
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
        with patch.object(details, "Path", return_value=Mock(read_text=lambda: fixture)), patch.object(details, "command", return_value="42 worker 0.0 256\n"):
            result = details.collect("memory")
        self.assertEqual(result["summaries"][0]["fraction"], .5)
        self.assertEqual(result["rows"][0]["fraction"], .25)

    def test_storage_percentage_uses_total_not_df_reserved_space_percent(self):
        with patch.object(details, "command", return_value="header\n/dev/a / 100 20 20 50%\n"):
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
        with patch.object(details, "command", return_value="123 worker 1.0 1024\n"):
            row = details.processes("rss", capacity=4 * 1024 * 1024)[0]
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
        line = "123 worker process 2.5 1024\n"
        with patch.object(details, "command", return_value=line * 12):
            rows = details.processes("rss")
        self.assertEqual(len(rows), 10)
        self.assertEqual(rows[0]["label"], "worker process · PID 123")
        self.assertIn("1.0 MiB", rows[0]["value"])

    def test_storage_deduplicates_devices_and_preserves_mount_spaces(self):
        fixture = "header\n/dev/a / 10240 2048 8192 20%\n/dev/a /home 10240 2048 8192 20%\n/dev/b /media/My Disk 4096 1024 3072 25%\ntmpfs /run 1024 100 924 10%\n"
        with patch.object(details, "command", return_value=fixture):
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
