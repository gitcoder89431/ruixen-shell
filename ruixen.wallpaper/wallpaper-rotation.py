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

def next_artwork(c):
    images=[]
    with os.scandir(c['folder']) as entries:
        for index,entry in enumerate(entries):
            if index >= 10000: raise ValueError('Folder exceeds 10000 entries; choose a smaller folder')
            if Path(entry.name).suffix.lower() in ('.png','.jpg','.jpeg','.webp','.avif') and entry.is_file():
                images.append(str(Path(entry.path).resolve()))
    images=sorted(set(images))
    if not images: raise ValueError('No supported artwork in this folder')
    current=str((Path.home()/'.local/state/omarchy/current/background').resolve())
    if c.get('shuffle', False):
        return random.choice([image for image in images if image != current] or images)
    index=(images.index(current)+1)%len(images) if current in images else 0
    return images[index]

if __name__=='__main__':
    try:
        action=sys.argv[1]
        if action=='configure': print(json.dumps(configure(json.loads(sys.argv[2]))))
        elif action=='next': print(json.dumps(dict(path=next_artwork(load()))))
        else: print(json.dumps(load()))
    except (ValueError,OSError,KeyError) as e:
        print(json.dumps(dict(error=str(e))))
        sys.exit(1)
