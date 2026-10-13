#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

class RotationTests(unittest.TestCase):
    def test_qml_state_stays_in_sync(self):
        # WallpaperRotationState.qml used to live only in the notch
        # (its single cycling pill); the launcher's own Shuffle section
        # (direct-pick chips, WallpaperAppearancePanel.qml) now carries
        # a second copy -- same byte-identical-copy parity convention
        # tests/wallpaper-effects.py's own test_packaged_assets_stay_in_sync
        # already uses for the other shared wallpaper QML/shader assets.
        root = Path(__file__).resolve().parents[1]
        a = root / 'bars/widgets/ruixen.notch/WallpaperRotationState.qml'
        b = root / 'ruixen.launcher/extensions/wallpapers/WallpaperRotationState.qml'
        self.assertEqual(b.read_bytes(), a.read_bytes())

    def test_rotation_and_config(self):
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                self.assertFalse(module.load()['enabled'])
                self.assertFalse(module.load()['shuffle'])
                folder=Path(home)/'art with spaces';folder.mkdir()
                for name in ['A.JPG','B.webp','C.png','ignored.gif']: (folder/name).write_bytes(b'fixture')
                (folder/'subfolder').mkdir();(folder/'subfolder/ignored.png').touch()
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                self.assertEqual(module.load(),cfg)
                current=Path(home)/'.local/state/omarchy/current/background';current.parent.mkdir(parents=True)
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.JPG'))
                current.symlink_to(folder/'B.webp')
                self.assertEqual(module.next_artwork(cfg),str(folder/'C.png'))
                current.unlink();current.symlink_to(folder/'C.png')
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.JPG'))
                shuffled=module.configure(dict(shuffle=True))
                self.assertTrue(module.load()['shuffle'])
                for _ in range(30):
                    self.assertIn(module.next_artwork(shuffled),[str(folder/'A.JPG'),str(folder/'B.webp')])
                (folder/'A.JPG').unlink(); (folder/'B.webp').unlink()
                self.assertEqual(module.next_artwork(shuffled),str(folder/'C.png'))
                # Older configuration files migrate to sequential mode.
                legacy=dict(cfg); legacy.pop('shuffle')
                module.config_path().write_text(json.dumps(legacy))
                self.assertFalse(module.load()['shuffle'])
                before=module.config_path().read_bytes()
                for changes in [[], dict(version=2), dict(version=True), dict(intervalMinutes=0),dict(intervalMinutes=True),dict(enabled='yes'),dict(shuffle='yes'),dict(shuffle=1),dict(folder='relative')]:
                    with self.assertRaises(ValueError): module.configure(changes)
                    self.assertEqual(module.config_path().read_bytes(),before)
                for item in folder.iterdir():
                    if item.is_file(): item.unlink()
                with self.assertRaises(ValueError):module.next_artwork(cfg)
                folder.rename(Path(home)/'renamed')
                module.configure(dict(enabled=False,folder=str(Path(home)/'renamed')))
                self.assertFalse(module.load()['enabled'])
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old
if __name__=='__main__':unittest.main()
