#!/usr/bin/env python3
"""Validated rotation settings and bounded, non-recursive artwork discovery."""
import json, os, random, sys, tempfile
from pathlib import Path

def config_path():
    return Path.home()/'.local/state/ruixen/wallpaper-rotation.json'

def defaults():
    return dict(version=1, enabled=False, shuffle=False, folder=str(Path.home()/'Pictures/ruixen-wallpapers'), intervalMinutes=15)

def validate(data, check_folder=True):
    if not isinstance(data,dict): raise ValueError("Rotation settings must be an object")
    c=defaults()
    c.update({k:v for k,v in data.items() if k in c})
    if type(c['version']) is not int or c['version'] != 1: raise ValueError('Unsupported rotation settings version')
    if type(c['enabled']) is not bool: raise ValueError('enabled must be boolean')
    if type(c['shuffle']) is not bool: raise ValueError('shuffle must be boolean')
    if type(c['intervalMinutes']) is not int or not 1 <= c['intervalMinutes'] <= 1440:
        raise ValueError('interval must be 1–1440 minutes')
    if not isinstance(c['folder'],str) or not c['folder'].strip(): raise ValueError('Choose an artwork folder')
    folder=Path(c['folder']).expanduser()
    if not folder.is_absolute(): raise ValueError('Use an absolute folder path')
    if check_folder and c['enabled'] and not folder.is_dir(): raise ValueError('Artwork folder does not exist')
    c['folder']=str(folder)
    c['version']=1
    return c

def load():
    path=config_path()
    return validate(json.loads(path.read_text()), check_folder=False) if path.exists() else defaults()

def configure(data):
    if not isinstance(data,dict): raise ValueError("Rotation settings must be an object")
    current=load(); current.update(data); current=validate(current)
    path=config_path(); path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.wallpaper-rotation-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as out: json.dump(current,out); out.write('\n')
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    return current

def order_path():
    return Path.home()/'.local/state/ruixen/wallpaper-order.json'

def load_order():
    # Plain filenames, not full paths -- same file the Wallpaper
    # Shuffle launcher extension writes directly (no IPC round-trip
    # needed for this, same "shared state file, multiple writers"
    # precedent wallpaper-appearance.json already uses). Fails closed
    # to an empty order rather than raising: a missing/corrupt order
    # file should just mean "no explicit order yet", never break
    # rotation outright.
    path=order_path()
    if not path.exists(): return []
    try:
        data=json.loads(path.read_text())
        order=data.get('order') if isinstance(data,dict) else None
        return [name for name in order if isinstance(name,str)] if isinstance(order,list) else []
    except (ValueError,OSError):
        return []

def save_order(order):
    # Same atomic-write shape as configure() above. Called by
    # next_artwork() itself (sequential mode only) to rotate the
    # persisted order, not by the launcher extension this time -- see
    # that call site's own comment for why.
    path=order_path(); path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.wallpaper-order-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as out: json.dump({'version':1,'order':order},out); out.write('\n')
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def ignored_path():
    return Path.home()/'.local/state/ruixen/wallpaper-ignored.json'

def load_ignored():
    # Same shape and same fail-closed reasoning as load_order() above --
    # plain filenames, written directly by the Wallpaper Shuffle
    # extension's own Tab -> Ignore action, no IPC round-trip. A
    # missing/corrupt file just means nothing is ignored yet.
    path=ignored_path()
    if not path.exists(): return set()
    try:
        data=json.loads(path.read_text())
        ignored=data.get('ignored') if isinstance(data,dict) else None
        return set(name for name in ignored if isinstance(name,str)) if isinstance(ignored,list) else set()
    except (ValueError,OSError):
        return set()

def reconciled_images(c):
    # Video/GIF included now -- Service.qml's own pause-during-playback
    # only backs off for a video/GIF someone set manually; a video/GIF
    # rotation picks itself no longer trips it (paused checks the path
    # against WallpaperRotation's own lastAppliedPath), so the normal
    # interval timer advances past one exactly like it would an image.
    images=[]
    with os.scandir(c['folder']) as entries:
        for index,entry in enumerate(entries):
            if index >= 10000: raise ValueError('Folder exceeds 10000 entries; choose a smaller folder')
            if Path(entry.name).suffix.lower() in ('.png','.jpg','.jpeg','.webp','.avif','.gif','.mp4','.mkv','.webm','.mov','.m4v') and entry.is_file():
                images.append(str(Path(entry.path).resolve()))
    images=sorted(set(images))
    if not images: raise ValueError('No supported artwork in this folder')
    # Ignored wallpapers are excluded from the candidate pool entirely,
    # same as if they weren't in the folder -- applies to both shuffle
    # and sequential mode since this runs before either one picks.
    # Checked separately from the "folder is genuinely empty" case
    # above so the error here says why, not just that nothing's there.
    ignored=load_ignored()
    if ignored:
        images=[p for p in images if Path(p).name not in ignored]
        if not images: raise ValueError('Every wallpaper in this folder is ignored')
    # Reconcile the persisted order (if any) against what's actually in
    # the folder right now, rather than trusting it as a cached file
    # list: drop anything no longer present, append anything new to the
    # end. No persisted order yet means this is a no-op -- `images` was
    # already alphabetical, same default as before the Wallpaper
    # Shuffle extension existed.
    by_name={Path(p).name:p for p in images}
    seen=set(); ordered=[]
    for name in load_order():
        if name in by_name and name not in seen:
            ordered.append(by_name[name]); seen.add(name)
    for p in images:
        name=Path(p).name
        if name not in seen:
            ordered.append(p); seen.add(name)
    return ordered

def next_artwork(c):
    images=reconciled_images(c)
    current=str((Path.home()/'.local/state/omarchy/current/background').resolve())
    if c.get('shuffle', False):
        return random.choice([image for image in images if image != current] or images)
    index=(images.index(current)+1)%len(images) if current in images else 0
    # Live queue: current always sits at the front of the persisted
    # order, retired to the back the moment something else becomes
    # current -- direct ask ("make this left panel list live so
    # current is ontop, when it rotates it goes to the buttom... like
    # a live que"), now that shuffle is off and sequential mode is the
    # one actually driving playback (shuffle's own random.choice above
    # has no stable position to rotate around, so this only runs
    # here). A cyclic rotation of the WHOLE list, not just moving the
    # old current to the end, so every other item keeps its relative
    # order -- a real round-robin queue. The Wallpaper Shuffle
    # extension needs no new code for this: it already live-reloads
    # this exact file on change and just displays whatever's in it.
    save_order([Path(p).name for p in images[index:] + images[:index]])
    return images[index]

def rotate_to(name, c):
    # Same rotation next_artwork() does for its own sequential pick,
    # triggered by a manual "Set as wallpaper" instead of a timer tick --
    # otherwise a manual pick leaves the queue showing stale order until
    # rotation itself happens to fire again (or never, if it's off).
    # Silently a no-op for a name outside the configured folder/ignored
    # set (nothing we can reorder it against) or while shuffle is on
    # (shuffle has no stable position to rotate around, same reasoning
    # as next_artwork's own shuffle branch above).
    if c.get('shuffle', False): return
    images=reconciled_images(c)
    by_name={Path(p).name:p for p in images}
    if name not in by_name: return
    index=images.index(by_name[name])
    save_order([Path(p).name for p in images[index:] + images[:index]])

if __name__=='__main__':
    try:
        action=sys.argv[1]
        if action=='configure': print(json.dumps(configure(json.loads(sys.argv[2]))))
        elif action=='next': print(json.dumps(dict(path=next_artwork(load()))))
        elif action=='mark-current': rotate_to(sys.argv[2], load()); print(json.dumps(dict(ok=True)))
        else: print(json.dumps(load()))
    except (ValueError,OSError,KeyError) as e:
        print(json.dumps(dict(error=str(e))))
        sys.exit(1)
