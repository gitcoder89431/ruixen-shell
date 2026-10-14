#!/usr/bin/env python3
"""Persist a validated GUI snapshot atomically, preserving unrelated settings."""
# Issue #105: this is now the one real, hand-maintained copy. Every
# picker UI that needs it (ruixen.launcher's Wallpapers extension,
# ruixen.notch) gets its own copy deployed here by install.sh
# (inject_shared_wallpaper_files) at install/update time -- plugins must
# be self-contained directories (no cross-plugin imports), so each
# still carries a real file on disk, just no longer a hand-copied one.
# Edit only here; tests/wallpaper-effects.py exercises this file
# directly, and tests/install-shared-wallpaper-files.sh proves
# install.sh actually deploys an identical copy to both picker UIs.
import json, math, os, re, subprocess, sys, tempfile
from pathlib import Path

def defaults():
    return dict(version=1, transitionEffect="reveal", transitionDurationMs=420,
                transitionSoftness=.02, ambientZoom=False, ambientGlow=False,
                disableMotion=False, backgroundEffect="none", backgroundIntensity=.25,
                backgroundSpeed=1, transitionOptions={})

def config_path():
    return Path.home() / ".local/state/ruixen/wallpaper-appearance.json"

def load():
    path=config_path()
    # One-time, read-only import of settings from the earlier prototype.
    legacy=Path.home()/".config/omarchy/ambient-wallpaper.json"
    raw=json.loads((path if path.exists() else legacy).read_text()) if path.exists() or legacy.exists() else {}
    if not isinstance(raw,dict): raise ValueError("Appearance settings must be an object")
    return dict(defaults(), **validate(dict(defaults(), **raw)))

def validate(data):
    if not isinstance(data,dict): raise ValueError("Appearance settings must be an object")
    if type(data.get("version", 1)) is not int or data.get("version", 1) != 1:
        raise ValueError("Unsupported appearance settings version")
    result = {"version": 1}
    effect = data.get("transitionEffect")
    if effect not in ('reveal', 'bleed', 'pixel-dissolve', 'iris', 'shutters', 'scanline', 'ink-spread', 'aurora', 'vortex', 'signal-tear', 'datamosh', 'vhs', 'code-bleed'):
        raise ValueError("Unknown transition")
    result["transitionEffect"] = effect
    for key, low, high in (("transitionDurationMs", 0, 30000), ("transitionSoftness", .001, .5)):
        value = data[key]
        if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
            raise ValueError("Invalid " + key)
        result[key] = int(value) if key == "transitionDurationMs" else value
    for key in ("ambientZoom", "ambientGlow", "disableMotion"):
        if type(data[key]) is not bool:
            raise ValueError("Invalid " + key)
        result[key] = data[key]
    if "transitionOptions" in data:
        options=data["transitionOptions"]
        if not isinstance(options,dict) or any(k not in ('signal-tear','datamosh','vhs','code-bleed') for k in options):
            raise ValueError("Invalid transition options")
        for entry in options.values():
            if not isinstance(entry,dict) or any(k not in ('strength','density') for k in entry):
                raise ValueError("Invalid transition controls")
            for key,value in entry.items():
                low,high=(0,1) if key=='strength' else (.5,2)
                if type(value) not in (int,float) or not math.isfinite(value) or not low <= value <= high:
                    raise ValueError("Invalid transition " + key)
        result["transitionOptions"]=options
    if "backgroundEffect" in data:
        if data["backgroundEffect"] not in ("none", "crt", "matrix"):
            raise ValueError("Unknown background effect")
        result["backgroundEffect"] = data["backgroundEffect"]
    for key, low, high in (("backgroundIntensity", 0, 1), ("backgroundSpeed", .1, 3)):
        if key in data:
            value = data[key]
            if type(value) not in (int, float) or not math.isfinite(value) or not low <= value <= high:
                raise ValueError("Invalid " + key)
            result[key] = value
    return result

def save(data):
    updates = validate(data)
    path = config_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    current = json.loads(path.read_text()) if path.exists() else load()
    if not isinstance(current,dict): raise ValueError("Appearance settings must be an object")
    if type(current.get("version",1)) is not int or current.get("version",1)!=1:
        raise ValueError("Unsupported appearance settings version")
    current.update(updates)
    fd, temporary = tempfile.mkstemp(prefix=".ambient-wallpaper-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(current, stream, indent=2)
            stream.write("\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def renderer_status():
    installed=(Path.home()/".config/omarchy/plugins/ruixen.background/manifest.json").is_file()
    try:
        current=load()
    except (ValueError,OSError) as error:
        current=defaults()
        current['error']='Unable to read appearance settings: '+str(error)
    current.update(installed=installed, rendererEnabled=False)
    if installed:
        try:
            response=subprocess.run(["omarchy-shell","ruixen-wallpaper-appearance","status"],capture_output=True,text=True,timeout=3)
            if response.returncode==0:
                state=json.loads(response.stdout)
                current.update(rendererEnabled=state.get("rendererEnabled") is True, error=state.get("error") or current.get("error", ""))
        except (OSError,ValueError,subprocess.TimeoutExpired):
            pass
    return current

def enable_renderer():
    if not (Path.home()/".config/omarchy/plugins/ruixen.background/manifest.json").is_file():
        raise ValueError("Install the Ruixen background plugin first")
    # Enabling a second clone can register duplicate background IPC handlers.
    # Refuse competing replacements; never silently disable someone else's plugin.
    result=subprocess.run(["omarchy","plugin","list","--json"],capture_output=True,text=True,timeout=10,check=True)
    for plugin in json.loads(result.stdout):
        ident=plugin.get("id", "")
        if not plugin.get("enabled") or ident in ("ruixen.background","omarchy.background") or not re.fullmatch(r"[A-Za-z0-9_.-]+",ident):
            continue
        manifest=Path.home()/".config/omarchy/plugins"/ident/"manifest.json"
        if manifest.is_file() and json.loads(manifest.read_text()).get("omarchy",{}).get("clonedFrom")=="omarchy.background":
            raise ValueError("Disable " + ident + " before enabling the Ruixen renderer")
    save(load())
    subprocess.run(["omarchy","plugin","enable","ruixen.background"],capture_output=True,text=True,timeout=10,check=True)

if __name__ == "__main__":
    try:
        action=sys.argv[1]
        if action=="status": print(json.dumps(renderer_status()))
        elif action=="enable": enable_renderer(); print(json.dumps(renderer_status()))
        elif action=="disable":
            subprocess.run(["omarchy","plugin","disable","ruixen.background"],capture_output=True,text=True,timeout=10,check=True)
            print(json.dumps(renderer_status()))
        else: save(json.loads(action))
    except (ValueError,OSError,subprocess.SubprocessError) as error:
        print(json.dumps(dict(error=str(error))))
        sys.exit(1)
