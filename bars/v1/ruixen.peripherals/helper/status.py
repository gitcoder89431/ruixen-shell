#!/usr/bin/env python3
"""Read-only sysfs snapshot of wireless peripherals.

Ported from github.com/xgborgeso/omarchy-peripheral-batteries (MIT license,
Copyright (c) Gabriel Borges) -- that plugin already solved the hard part
here: Quickshell's own Quickshell.Bluetooth (.battery/.batteryAvailable,
which wraps BlueZ's Battery1 D-Bus interface) and Quickshell.Services.UPower
both have real coverage gaps confirmed live on a real machine before this
was ported -- BlueZ's Battery1 isn't populated for at least one real
Bluetooth keyboard despite UPower reporting its battery correctly, and
neither binding sees non-Bluetooth USB wireless receivers (Logitech Bolt/
Unifying/Lightspeed dongles) at all. Reading /sys directly, the same way
this file does, is the only approach that covers both cases.

Notification/threshold logic from the original Service.qml was NOT ported
-- out of scope for this plugin's own first pass (pin-to-bar-icon, not
alerts). This file's own detection/classification logic otherwise matches
the source, with one deliberate deviation: merge() treats an Apple
Bluetooth device reporting exactly 0 as unavailable rather than a real
0%, working around a real kernel-level battery-refresh gap (see merge()'s
own comment). The source repo's own notifyPlan() has no such guard --
confirmed by reading its actual logic, not assumed -- so it is not a gap
this file inherited by omission.

Never opens /dev/hidraw. JSON on stdout, always exit 0.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional

SCHEMA_VERSION = 1

# A USB or Bluetooth peripheral chooses its own product and manufacturer strings,
# so every field that reaches the shell is attacker-controlled. Cap each one, and
# cap the whole payload, so a hostile descriptor cannot spend the shell's memory
# or push a wall of text through the panel.
FIELD_LIMIT = 96
ERROR_LIMIT = 160
TOTAL_LIMIT = 64 * 1024
DEVICE_LIMIT = 32
LEVEL_UNKNOWN = -1

LOGITECH_VID = 0x046D
ITE_VID = 0x048D
HYPERX_VID = 0x0951

LIGHTSPEED_PIDS = {0xC547, 0xC53F, 0xC539, 0xC537}
BOLT_PIDS = {0xC548}
UNIFYING_PIDS = {0xC52B, 0xC532, 0xC537}

BRAND_FROM_VID = {
    0x046D: "Logitech",
    0x1532: "Razer",
    0x054C: "Sony",
    0x1038: "SteelSeries",
    0x045E: "Microsoft",
    0x05AC: "Apple",
    # A Bluetooth HID_ID's vendor field is a Bluetooth SIG company id, a
    # separate namespace from USB vendor ids -- Apple's USB vid (0x05AC,
    # above) never appears there. Confirmed live on real hardware (a
    # Magic Keyboard's own HID_ID reads 0005:0000004C:...): Apple, Inc. is
    # assigned company id 0x004C (76) in the Bluetooth SIG's own list.
    # Without this, no Bluetooth-connected Apple device is ever
    # recognized as Apple at all -- see merge()'s own Apple/Bluetooth/
    # stale-zero guard, which silently never fired without this entry.
    0x004C: "Apple",
    0x0951: "HyperX",
    0x1B1C: "Corsair",
}

PRODUCT_STRIP = (
    "logitech",
    "kingston",
    "razer",
    "steelseries",
    "corsair",
    "microsoft",
    "apple",
    "sony",
    "samsung",
    "hyperx",
    "wireless",
    "usb",
)


@dataclass
class Device:
    id: str
    name: str
    brand: str
    kind: str
    transport: str
    level: int
    remaining_sec: int
    status: str
    charging: bool
    available: bool

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "brand": self.brand,
            "kind": self.kind,
            "transport": self.transport,
            "level": self.level,
            "remaining_sec": self.remaining_sec,
            "status": self.status,
            "charging": self.charging,
            "available": self.available,
        }


@dataclass
class Hid:
    name: str
    uniq: str
    vid: int
    pid: int
    bus: int
    driver: str


@dataclass
class Pack:
    name: str
    manufacturer: str
    model: str
    serial: str
    level: int
    remaining_sec: int
    status: str
    charging: bool
    scope: str
    type_name: str
    sys_name: str


def sysfs_root() -> Path:
    return Path(os.environ.get("PERIPHERALS_SYSFS", "/sys"))


def read_file(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def collect() -> list[Device]:
    return collect_from(sysfs_root())


def collect_from(root: Path) -> list[Device]:
    packs = read_packs(root / "class" / "power_supply")
    hids = read_hids(root / "class" / "hidraw")
    return merge(packs, hids)


def read_packs(directory: Path) -> list[Pack]:
    if not directory.is_dir():
        return []
    packs: list[Pack] = []
    try:
        entries = list(directory.iterdir())
    except OSError:
        return []
    for entry in entries:
        if not entry.is_dir():
            continue
        sys_name = entry.name
        type_name = read_file(entry / "type")
        if type_name.lower() != "battery":
            continue
        scope = read_file(entry / "scope")
        serial = read_file(entry / "serial_number")
        model = read_file(entry / "model_name")
        manufacturer = read_file(entry / "manufacturer")
        status = read_file(entry / "status")
        charging = status.lower() in ("charging", "full")
        try:
            level = int(read_file(entry / "capacity"))
            if level < 0 or level > 100:
                level = LEVEL_UNKNOWN
        except ValueError:
            level = LEVEL_UNKNOWN
        packs.append(
            Pack(
                name=model if model else sys_name,
                manufacturer=manufacturer,
                model=model,
                serial=serial,
                level=level,
                remaining_sec=remaining_secs(entry, charging),
                status=status_token(status),
                charging=charging,
                scope=scope,
                type_name=type_name,
                sys_name=sys_name,
            )
        )
    return packs


def read_hids(directory: Path) -> list[Hid]:
    if not directory.is_dir():
        return []
    hids: list[Hid] = []
    try:
        entries = list(directory.iterdir())
    except OSError:
        return []
    for entry in entries:
        uevent = read_file(entry / "device" / "uevent")
        if not uevent:
            continue
        hid = parse_uevent(uevent)
        if hid is not None:
            hids.append(hid)
    return hids


def parse_uevent(text: str) -> Optional[Hid]:
    name = ""
    uniq = ""
    driver = ""
    hid_id = ""
    for line in text.splitlines():
        if line.startswith("HID_NAME="):
            name = line[len("HID_NAME=") :].strip()
        elif line.startswith("HID_UNIQ="):
            uniq = line[len("HID_UNIQ=") :].strip()
        elif line.startswith("DRIVER="):
            driver = line[len("DRIVER=") :].strip()
        elif line.startswith("HID_ID="):
            hid_id = line[len("HID_ID=") :].strip()
    parsed = parse_hid_id(hid_id)
    if parsed is None:
        return None
    bus, vid, pid = parsed
    return Hid(name=name, uniq=uniq, vid=vid, pid=pid, bus=bus, driver=driver)


def parse_hid_id(value: str) -> Optional[tuple[int, int, int]]:
    parts = value.split(":")
    if len(parts) < 3:
        return None
    try:
        bus = int(parts[0], 16)
        vid = int(parts[1], 16) & 0xFFFF
        pid = int(parts[2], 16) & 0xFFFF
    except ValueError:
        return None
    return bus, vid, pid


def is_laptop_pack(pack: Pack) -> bool:
    if pack.scope.lower() == "system":
        return True
    sys_name = pack.sys_name.lower()
    if pack.scope.lower() == "device":
        return False
    return sys_name.startswith("bat") or sys_name.startswith("cmb") or "macsmc" in sys_name


def is_receiver(hid: Hid) -> bool:
    return (
        hid.driver == "logitech-djreceiver"
        or hid.name.lower() == "logitech usb receiver"
        or "unifying receiver" in hid.name.lower()
    )


def is_internal(hid: Hid) -> bool:
    return hid.vid == ITE_VID or hid.name.lower().startswith("ite ")


def is_wired_ignored(hid: Hid) -> bool:
    return hid.vid == HYPERX_VID or "hyperx" in hid.name.lower()


def looks_wireless(hid: Hid) -> bool:
    if hid.bus == 0x0005:
        return True
    if hid.driver == "logitech-hidpp-device":
        return True
    if hid.vid == LOGITECH_VID and not is_receiver(hid):
        return True
    n = hid.name.lower()
    return any(token in n for token in ("lightspeed", "wireless", "bluetooth", "bolt", "unifying"))


def kind_of(name: str, hid: Optional[Hid]) -> str:
    n = name.lower()
    if "headset" in n or "headphone" in n or "earbuds" in n:
        return "headset"
    if "keyboard" in n or "keys" in n:
        return "keyboard"
    if "controller" in n or "gamepad" in n:
        return "controller"
    if "mouse" in n:
        return "mouse"
    if hid is not None and hid.vid == LOGITECH_VID:
        if "pro x" in n and "lightspeed" not in n:
            return "mouse"
        if hid.driver == "logitech-hidpp-device":
            return "mouse"
        hn = hid.name.lower()
        if "lightspeed" in hn and "mouse" not in hn:
            return "headset"
    return "unknown"


def transport_of(hid: Optional[Hid], pack_name: str) -> str:
    if hid is not None:
        if hid.bus == 0x0005:
            return "bluetooth"
        if hid.pid in LIGHTSPEED_PIDS or "lightspeed" in hid.name.lower():
            return "lightspeed"
        if hid.pid in BOLT_PIDS:
            return "bolt"
        if hid.pid in UNIFYING_PIDS:
            return "unifying"
        if hid.driver == "logitech-hidpp-device" or hid.vid == LOGITECH_VID:
            return "lightspeed"
        return "usb"
    if "lightspeed" in pack_name.lower():
        return "lightspeed"
    return "unknown"


def uniq_ok(value: str) -> bool:
    t = value.strip()
    if not t:
        return False
    return not all(c in "0-" for c in t)


def merge(packs: list[Pack], hids: list[Hid]) -> list[Device]:
    has_hidpp_child = any(h.driver == "logitech-hidpp-device" for h in hids)
    unique: dict[tuple[int, int, int, str], Hid] = {}
    for hid in hids:
        key = (hid.bus, hid.vid, hid.pid, hid.name)
        unique.setdefault(key, hid)
    hids = list(unique.values())

    devices: dict[str, Device] = {}
    claimed_serials: list[str] = []

    for pack in packs:
        if is_laptop_pack(pack):
            continue
        device_id = f"pack:{pack.serial}" if uniq_ok(pack.serial) else f"pack:{pack.sys_name}"
        hid = next(
            (
                h
                for h in hids
                if uniq_ok(h.uniq) and uniq_ok(pack.serial) and eq_serial(h.uniq, pack.serial)
            ),
            None,
        )
        if hid is None:
            hid = next(
                (
                    h
                    for h in hids
                    if not is_receiver(h)
                    and (h.name.lower() == pack.name.lower() or h.name.lower() == pack.model.lower())
                ),
                None,
            )
        if hid is not None and uniq_ok(hid.uniq):
            claimed_serials.append(hid.uniq)
        name = human_name(hid, pack)
        brand = brand_of(hid, pack.manufacturer, name)
        transport = transport_of(hid, name)
        level = pack.level
        remaining_sec = pack.remaining_sec
        status = pack.status
        charging = pack.charging
        available = pack.level != LEVEL_UNKNOWN

        # Apple's mainline hid-apple driver only actively re-fetches battery
        # over USB (a GET_REPORT that needs a sleepable context an existing
        # Bluetooth/uhid timer callback cannot provide -- see the in-review
        # "HID: apple: report battery over USB" kernel patch series). Over
        # Bluetooth the sysfs node can get stuck permanently at a stale 0
        # after a re-pair, which reads as a confident "needs charging now"
        # rather than "no reading yet". Confirmed live on real hardware
        # (ruixen-shell issue #37): a real 92% before a forget/re-pair cycle,
        # 0% and never recovering after. Narrow on purpose -- only brand
        # Apple, transport bluetooth, and exactly zero -- so an unrelated
        # device that legitimately drains to 0%, or an Apple device
        # connected over USB (which the driver does refresh), is untouched.
        if level == 0 and transport == "bluetooth" and brand.lower() == "apple":
            level = LEVEL_UNKNOWN
            remaining_sec = LEVEL_UNKNOWN
            status = "unknown"
            charging = False
            available = False

        devices[device_id] = Device(
            id=device_id,
            brand=brand,
            kind=kind_of(name, hid),
            transport=transport,
            name=name,
            level=level,
            remaining_sec=remaining_sec,
            status=status,
            charging=charging,
            available=available,
        )

    for hid in hids:
        if is_internal(hid) or is_wired_ignored(hid):
            continue
        if is_receiver(hid) and has_hidpp_child:
            continue
        if not looks_wireless(hid):
            continue
        if uniq_ok(hid.uniq) and any(eq_serial(s, hid.uniq) for s in claimed_serials):
            continue
        if any(d.name.lower() == hid.name.lower() for d in devices.values()):
            continue
        if uniq_ok(hid.uniq):
            device_id = f"hid:{hid.uniq}"
        else:
            device_id = f"hid:{hid.vid:04x}:{hid.pid:04x}:{slug(hid.name)}"
        devices[device_id] = Device(
            id=device_id,
            name=human_name(hid, None),
            brand=brand_of(hid, "", hid.name),
            kind=kind_of(hid.name, hid),
            transport=transport_of(hid, hid.name),
            level=LEVEL_UNKNOWN,
            remaining_sec=LEVEL_UNKNOWN,
            status="unknown",
            charging=False,
            available=False,
        )

    out = list(devices.values())
    out.sort(key=lambda d: (d.brand, d.kind, d.name))
    return out


def brand_of(hid: Optional[Hid], manufacturer: str, name: str) -> str:
    from_mfr = manufacturer.strip()
    if from_mfr and from_mfr.lower() != "unknown":
        return title_brand(from_mfr)
    if hid is not None:
        brand = BRAND_FROM_VID.get(hid.vid)
        if brand:
            return brand
    lower = name.lower()
    if "logitech" in lower:
        return "Logitech"
    if "razer" in lower:
        return "Razer"
    if "steelseries" in lower:
        return "SteelSeries"
    if "sony" in lower:
        return "Sony"
    return ""


def is_human_name(name: str) -> bool:
    n = name.strip()
    if not n:
        return False
    if len(n) == 9 and n[4:5] == ":" and all(c in "0123456789abcdefABCDEF:" for c in n):
        return False
    lower = n.lower()
    return not lower.startswith("hidpp_battery") and not lower.startswith("hidraw")


def human_name(hid: Optional[Hid], pack: Optional[Pack]) -> str:
    if hid is not None and is_human_name(hid.name):
        return hid.name.strip()
    if pack is not None:
        if is_human_name(pack.model):
            return pack.model.strip()
        if is_human_name(pack.name) and pack.name != pack.sys_name:
            return pack.name.strip()
    return ""


def status_token(raw: str) -> str:
    s = raw.strip().lower()
    if s in ("charging", "full", "discharging"):
        return s
    if not s:
        return "unknown"
    return s


def parse_positive_int(path: Path) -> int:
    try:
        n = int(read_file(path))
    except ValueError:
        return 0
    return n if n > 0 else 0


def parse_int_opt(path: Path) -> Optional[int]:
    text = read_file(path)
    try:
        return int(text)
    except ValueError:
        return None


def remaining_secs(path: Path, charging: bool) -> int:
    to_empty = parse_positive_int(path / "time_to_empty_now")
    to_full = parse_positive_int(path / "time_to_full_now")
    if charging and to_full > 0:
        return to_full
    if not charging and to_empty > 0:
        return to_empty
    charge = parse_int_opt(path / "charge_now")
    current = parse_int_opt(path / "current_now")
    if charge is not None and charge > 0 and current is not None and abs(current) > 0:
        return int(round((charge / abs(current)) * 3600.0))
    energy = parse_int_opt(path / "energy_now")
    power = parse_int_opt(path / "power_now")
    if energy is not None and energy > 0 and power is not None and abs(power) > 0:
        return int(round((energy / abs(power)) * 3600.0))
    return LEVEL_UNKNOWN


def title_brand(value: str) -> str:
    if not value:
        return "Other"
    return value[0].upper() + value[1:].lower()


def enrich_headsetcontrol(devices: list[Device]) -> None:
    try:
        output = subprocess.run(
            ["headsetcontrol", "-b", "-o", "json"],
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return
    if output.returncode != 0:
        return
    try:
        parsed = json.loads(output.stdout.decode("utf-8", errors="replace"))
    except json.JSONDecodeError:
        return
    apply_headsetcontrol_json(devices, parsed)


def apply_headsetcontrol_json(devices: list[Device], parsed: Any) -> None:
    if not isinstance(parsed, dict):
        return
    raw_list = parsed.get("devices")
    if not isinstance(raw_list, list):
        return
    for entry in raw_list:
        if not isinstance(entry, dict):
            continue
        product = ""
        for key in ("product", "device", "name"):
            value = entry.get(key)
            if isinstance(value, str) and value.strip():
                product = value.lower()
                break
        if not product:
            continue
        battery = entry.get("battery")
        if not isinstance(battery, dict):
            battery = entry
        level_raw = battery.get("level")
        if level_raw is None:
            level_raw = battery.get("percentage")
        try:
            level = int(level_raw)
        except (TypeError, ValueError):
            continue
        if level < 0 or level > 100:
            continue
        status = battery.get("status")
        charging = isinstance(status, str) and "charg" in status.lower()
        for device in devices:
            if device.kind != "headset":
                continue
            if product_matches(device.name, product):
                device.level = level
                device.charging = charging
                device.available = True


def normalize_product(s: str) -> str:
    n = s.lower()
    for word in PRODUCT_STRIP:
        n = n.replace(word, " ")
    return " ".join(n.split())


def product_matches(name: str, product: str) -> bool:
    a = normalize_product(name)
    b = normalize_product(product)
    if not a or not b:
        return False
    return a == b or a in b or b in a


def eq_serial(a: str, b: str) -> bool:
    return a.lower() == b.lower()


def slug(name: str) -> str:
    return "".join(c.lower() if c.isalnum() else "-" for c in name)


def clean_field(value: Any, limit: int = FIELD_LIMIT) -> str:
    """Flatten one device string into something safe to render.

    Control characters (including the newlines that would let one field forge
    extra lines in the panel) collapse to spaces, and the result is capped. The
    shell renders these as plain text, but a field that never carries markup or
    control bytes in the first place cannot depend on that.
    """
    text = value if isinstance(value, str) else ("" if value is None else str(value))
    text = "".join(ch if ch.isprintable() else " " for ch in text)
    text = " ".join(text.split())
    if len(text) > limit:
        text = text[:limit].rstrip()
    return text


def emit(status: dict[str, Any]) -> None:
    devices = status.get("devices")
    if isinstance(devices, list):
        if len(devices) > DEVICE_LIMIT:
            devices = devices[:DEVICE_LIMIT]
        for row in devices:
            if not isinstance(row, dict):
                continue
            for key in ("id", "name", "brand", "kind", "transport", "status"):
                if key in row:
                    row[key] = clean_field(row[key])
        status["devices"] = devices
    if "error" in status:
        status["error"] = clean_field(status["error"], ERROR_LIMIT)

    payload = json.dumps(status, separators=(",", ":"))
    # A payload past the cap means the device list itself is the problem, so drop
    # it rather than emit a truncated string the shell could not parse.
    if len(payload) > TOTAL_LIMIT:
        status["devices"] = []
        status["error"] = clean_field("Peripheral list too large to report", ERROR_LIMIT)
        payload = json.dumps(status, separators=(",", ":"))
    print(payload, flush=True)


def main() -> None:
    try:
        devices = collect()
        enrich_headsetcontrol(devices)
        emit(
            {
                "ok": True,
                "schema_version": SCHEMA_VERSION,
                "error": "",
                "devices": [d.as_dict() for d in devices],
            }
        )
    except Exception as err:
        emit(
            {
                "ok": False,
                "schema_version": SCHEMA_VERSION,
                "error": str(err),
                "devices": [],
            }
        )


if __name__ == "__main__":
    main()
