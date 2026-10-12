#!/usr/bin/env python3
"""Read-only, bounded system details for the dashboard's open detail page."""
import argparse
import json
import os
import re
import selectors
from itertools import islice
from pathlib import Path
import subprocess
import time


def command(args):
    # Bound the buffer while reading, rather than checking after capture_output.
    environment = dict(os.environ, LC_ALL="C")
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          env=environment) as process:
        try:
            output = bytearray()
            deadline = time.monotonic() + 3
            with selectors.DefaultSelector() as selector:
                selector.register(process.stdout, selectors.EVENT_READ)
                while True:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not selector.select(remaining):
                        raise subprocess.TimeoutExpired(args, 3)
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    output.extend(chunk)
                    if len(output) > 1024 * 1024:
                        raise ValueError("Output too large")
            code = process.wait(timeout=max(.001, deadline - time.monotonic()))
            if code:
                raise subprocess.CalledProcessError(code, args)
            return output.decode("utf-8", errors="replace")
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()


def size(value):
    value = float(value)
    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}"
        value /= 1024


def processes(order, capacity=None):
    rows = []
    output = command(["ps", "-eo", "pid=,comm=,pcpu=,rss=", "--sort=-" + order])
    for line in output.splitlines()[:10]:
        parts = line.split()
        if len(parts) < 4:
            continue
        pid, name, cpu, rss = parts[0], " ".join(parts[1:-2]), parts[-2], parts[-1]
        amount = int(rss) * 1024
        row = {"label": f"{name} · PID {pid}", "value": f"{cpu}% CPU · {size(amount)} RAM"}
        if capacity:
            share = amount / capacity
            row.update(value=size(amount) + f" · {share * 100:.1f}% of RAM", fraction=share)
        rows.append(row)
    return rows


def cpu_snapshot():
    values = [int(v) for v in Path("/proc/stat").read_text().splitlines()[0].split()[1:9]]
    total, idle = sum(values), values[3] + values[4]
    items = {}
    for proc in islice(Path("/proc").iterdir(), 8192):
        if not proc.name.isdigit():
            continue
        try:
            stat = (proc / "stat").read_text()
            end = stat.rfind(")")
            fields = stat[end + 2:].split()
            # PID plus start time prevents attributing a reused PID's old ticks.
            items[(proc.name, fields[19])] = (stat[stat.index("(") + 1:end], int(fields[11]) + int(fields[12]))
        except (OSError, ValueError, IndexError):
            continue
    return total, idle, items


def rank_cpu(before, after, elapsed, cores, ticks, capacity_ticks=None, limit=10):
    rows = []
    for identity, (name, counter) in after.items():
        if identity not in before:
            continue
        delta = max(0, counter - before[identity][1])
        used_cores = delta / ticks / elapsed
        share = min(1, delta / capacity_ticks) if capacity_ticks else min(1, used_cores / cores)
        if capacity_ticks:
            used_cores = share * cores
        rows.append({"label": name + " · PID " + identity[0],
                     "value": f"{share * 100:.1f}% of total CPU", "fraction": share,
                     "detail": f"{used_cores:.2f} cores · {cores} logical CPUs available"})
    return sorted(rows, key=lambda row: row["fraction"], reverse=True)[:limit]


def drm_fields(text):
    fields = dict(line.split(":", 1) for line in text.splitlines() if line.startswith("drm-") and ":" in line)
    fields = {k: v.strip() for k, v in fields.items()}
    if "drm-client-id" not in fields or "drm-driver" not in fields:
        return None
    engines, capacities, memory = {}, {}, {}
    for key, value in fields.items():
        if key.startswith("drm-engine-capacity-"):
            capacities[key.removeprefix("drm-engine-capacity-")] = max(1, int(value))
        elif key.startswith("drm-engine-") and value.endswith(" ns"):
            engines[key.removeprefix("drm-engine-")] = int(value.split()[0])
    for region in ["vram", "gtt", "system", "memory"]:
        value = fields.get("drm-resident-" + region, fields.get("drm-memory-" + region))
        if value is not None:
            parts = value.split()
            factor = {"B": 1, "KiB": 1024, "MiB": 1024 ** 2}.get(parts[1] if len(parts) > 1 else "B")
            if factor is not None:
                memory[region] = int(parts[0]) * factor
    identity = (fields.get("drm-pdev", fields["drm-driver"]), fields["drm-client-id"])
    return identity, engines, capacities, memory


def gpu_snapshot():
    clients = {}
    deadline = time.monotonic() + 2
    for proc in islice(Path("/proc").iterdir(), 8192):
        if not proc.name.isdigit():
            continue
        if time.monotonic() > deadline:
            break
        try:
            with os.scandir(proc / "fd") as descriptors:
                for index, fd in enumerate(descriptors):
                    if index >= 512 or time.monotonic() > deadline:
                        break
                    try:
                        if not os.readlink(fd.path).startswith("/dev/dri/"):
                            continue
                        parsed = drm_fields((proc / "fdinfo" / fd.name).read_text())
                        if not parsed or parsed[0] in clients:
                            continue
                        identity, engines, capacities, memory = parsed
                        clients[identity] = {"pid": proc.name, "name": (proc / "comm").read_text().strip(),
                                             "sampledAt": time.monotonic(),
                                             "engines": engines, "capacities": capacities, "memory": memory}
                    except (OSError, ValueError):
                        continue
        except OSError:
            continue
    return clients


def rank_gpu(before, after, elapsed):
    processes = {}
    for identity, client in after.items():
        proc = processes.setdefault(client["pid"], {"name": client["name"], "engines": {}, "vram": 0, "shared": 0})
        proc["vram"] += client["memory"].get("vram", 0)
        proc["shared"] += client["memory"].get("gtt", client["memory"].get("system", client["memory"].get("memory", 0)))
        previous = before.get(identity)
        if not previous or previous["pid"] != client["pid"]:
            continue
        interval = client.get("sampledAt", elapsed) - previous.get("sampledAt", 0)
        if interval <= 0:
            continue
        for engine, counter in client["engines"].items():
            if engine not in previous["engines"]:
                continue
            share = max(0, counter - previous["engines"][engine]) / interval / 1e9 / client["capacities"].get(engine, 1)
            key = identity[0] + ":" + engine
            proc["engines"][key] = proc["engines"].get(key, 0) + share
    rows = []
    for pid, proc in processes.items():
        share = min(1, max(proc["engines"].values())) if proc["engines"] else None
        rows.append({"label": proc["name"] + " · PID " + pid,
                     "value": f"{share * 100:.1f}% busiest engine" if share is not None else "Engine usage unreported",
                     "fraction": share,
                     "detail": size(proc["vram"]) + " VRAM · " + size(proc["shared"]) + " shared GPU RAM",
                     "memoryBytes": proc["vram"] + proc["shared"]})
    return sorted(rows, key=lambda row: (row["fraction"] or 0, row["memoryBytes"]), reverse=True)[:10]


def collect(kind):
    rows = []
    summaries = []
    note = "Read-only snapshot; refreshed while this page is open."
    if kind == "cpu":
        first = cpu_snapshot()
        start = time.monotonic()
        time.sleep(.4)
        second = cpu_snapshot()
        elapsed = time.monotonic() - start
        cores = os.cpu_count() or 1
        total_delta = second[0] - first[0]
        busy = max(0, min(1, 1 - (second[1] - first[1]) / total_delta)) if total_delta > 0 else 0
        all_rows = rank_cpu(first[2], second[2], elapsed, cores, os.sysconf("SC_CLK_TCK"), capacity_ticks=total_delta, limit=8192)
        rows = all_rows[:10]
        listed = sum(row["fraction"] for row in rows)
        other = sum(row["fraction"] for row in all_rows[10:])
        remainder = max(0, busy - listed - other)
        detail = f"Listed processes: {listed * 100:.1f}% · Other readable processes: {other * 100:.1f}% · Unattributed/system: {remainder * 100:.1f}%"
        if listed + other > busy + .005:
            detail += " · counter timing differs slightly"
        summaries = [{"label": "Whole-machine CPU in use", "value": f"{busy * 100:.1f}%", "fraction": busy, "detail": detail,
                      "breakdown": {"listed": listed, "other": other, "unattributed": remainder}}]
        rows += [{"label": "Logical CPUs", "value": str(cores)},
                 {"label": "Load averages · 1 / 5 / 15 min", "value": " / ".join(f"{v:.2f}" for v in os.getloadavg())}]
        note = "0.4-second sample · percentages use total CPU capacity. Unattributed/system includes time outside matched readable processes; row values are rounded."
    elif kind == "memory":
        data = {}
        for line in Path("/proc/meminfo").read_text().splitlines():
            key, value = line.split(":", 1)
            data[key] = int(value.split()[0]) * 1024
        for label, key in [("Physical memory", "MemTotal"), ("Available", "MemAvailable"),
                           ("Page cache", "Cached"), ("Swap total", "SwapTotal"), ("Swap free", "SwapFree")]:
            rows.append({"label": label, "value": size(data.get(key, 0))})
        total = data.get("MemTotal", 0)
        available = data.get("MemAvailable")
        if total <= 0 or available is None or not 0 <= available <= total:
            raise ValueError("Missing or invalid RAM capacity")
        used = total - available
        summaries = [{"label": "RAM in use / total", "value": size(used) + " / " + size(total), "fraction": used / total,
                      "detail": "Used = total − available. Process RSS rows overlap and do not sum to this total."}]
        rows = processes("rss", total) + rows
        note = "Resident RAM · percentages use physical RAM. Shared pages can appear in multiple processes."
    elif kind == "network":
        routes = json.loads(command(["ip", "-j", "route", "show", "default"]))
        for route in routes[:8]:
            rows.append({"label": "Default route · " + route.get("dev", "Unknown"), "value": route.get("gateway", "Direct route")})
        for device in json.loads(command(["ip", "-j", "address", "show"]))[:32]:
            name = device.get("ifname", "Unknown")
            rows.append({"label": name, "value": device.get("operstate", "Unknown")})
            for addr in device.get("addr_info", [])[:8]:
                rows.append({"label": "  " + addr.get("family", "IP"), "value": str(addr.get("local", "")) + "/" + str(addr.get("prefixlen", ""))})
        note = "Interface state and addresses. Dashboard transfer totals are counters since the interface came up, not a billing-period total."
    elif kind == "storage":
        seen = set()
        for line in command(["df", "-B1", "--output=source,target,size,used,avail,pcent"]).splitlines()[1:][:128]:
            parts = line.rsplit(None, 4)
            if len(parts) != 5:
                continue
            source_mount, total, used, available, percent = parts
            source, mount = source_mount.split(None, 1)
            if not source.startswith("/dev/") or source in seen:
                continue
            seen.add(source)
            total_bytes, used_bytes, available_bytes = int(total), int(used), int(available)
            if total_bytes <= 0 or used_bytes < 0 or available_bytes < 0:
                continue
            rows.extend([{"label": mount + " · " + source, "value": f"{used_bytes / total_bytes * 100:.1f}% capacity used"},
                         {"label": "  Used / total", "value": size(used) + " / " + size(total)},
                         {"label": "  Available", "value": size(available)}])
        note = "Device-backed filesystems · used ÷ total capacity, matching the overview. Available space can exclude reserved space. Amounts use binary units."
    elif kind == "gpu":
        seen = set()
        for card in sorted(Path("/sys/class/drm").glob("card[0-9]*")):
            if not re.fullmatch(r"card\d+", card.name):
                continue
            device = card / "device"
            if not device.exists() or device.resolve() in seen:
                continue
            seen.add(device.resolve())
            driver = device / "driver"
            rows.append({"label": card.name + " · driver", "value": driver.resolve().name if driver.exists() else "Unknown"})
            for label, filename, formatter in [
                ("Busy", "gpu_busy_percent", lambda v: v + "%"),
                ("Dedicated VRAM total", "mem_info_vram_total", size),
                ("Dedicated VRAM used", "mem_info_vram_used", size),
            ]:
                try:
                    raw = (device / filename).read_text().strip()
                    value = formatter(raw)
                    if filename == "gpu_busy_percent":
                        busy = int(raw)
                        if not 0 <= busy <= 100:
                            raise ValueError("Invalid GPU busy reading")
                        summaries.append({"label": card.name + " · device GPU busy", "value": value, "fraction": busy / 100,
                                          "detail": "Device-wide driver reading. Process engine percentages are not additive."})
                except (OSError, ValueError):
                    value = "Not exposed by this driver"
                rows.append({"label": "  " + label, "value": value})
            for sensor in sorted(device.glob("hwmon/hwmon*/temp1_input"))[:4]:
                try:
                    rows.append({"label": "  Device temperature", "value": f"{int(sensor.read_text()) / 1000:.1f} °C"})
                except (OSError, ValueError):
                    pass
        before = gpu_snapshot()
        start = time.monotonic()
        time.sleep(.4)
        after = gpu_snapshot()
        elapsed = time.monotonic() - start
        ranked = rank_gpu(before, after, elapsed)
        rows = ranked + rows
        note = "Accessible GPU processes · percentages use the busiest engine, not additive whole-device usage. Shared buffers may be counted more than once."
        if not ranked:
            note = "Per-process GPU counters are inaccessible or not exposed. Device sensors are shown below."
    return {"kind": kind, "rows": rows, "summaries": summaries, "note": note, "error": ""}



if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["cpu", "gpu", "memory", "network", "storage"])
    args = parser.parse_args()
    try:
        result = collect(args.kind)
    except Exception:
        result = {"kind": args.kind, "rows": [], "note": "", "error": "Unable to read system details. Try refreshing."}
    print(json.dumps(result))
