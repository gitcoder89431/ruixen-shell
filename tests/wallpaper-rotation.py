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

    def test_order_reconciliation(self):
        # The Wallpaper Shuffle launcher extension writes
        # ~/.local/state/ruixen/wallpaper-order.json directly (plain
        # filenames, no IPC round-trip -- same shared-state-file
        # precedent wallpaper-appearance.json already uses), and
        # next_artwork reconciles it against the live folder on every
        # call: explicit order wins, a file no longer present is
        # dropped silently, a file not yet in the order is appended at
        # the end rather than breaking the whole sequence.
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_order',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                for name in ['A.jpg','B.jpg','C.jpg']: (folder/name).write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                bg=Path(home)/'.local/state/omarchy/current/background';bg.parent.mkdir(parents=True)
                # No order file yet -- falls back to alphabetical, same
                # as before this feature existed.
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.jpg'))
                order_path=Path(home)/'.local/state/ruixen/wallpaper-order.json'
                order_path.write_text(json.dumps({'version':1,'order':['C.jpg','A.jpg','B.jpg']}))
                bg.symlink_to(folder/'C.jpg')
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.jpg'))
                # A file referenced by the order but deleted from disk
                # is dropped silently, not an error.
                (folder/'A.jpg').unlink()
                self.assertEqual(module.next_artwork(cfg),str(folder/'B.jpg'))
                # A file that exists but was never in the order is
                # appended at the end, not inserted mid-sequence.
                (folder/'D.jpg').write_bytes(b'x')
                bg.unlink();bg.symlink_to(folder/'B.jpg')
                self.assertEqual(module.next_artwork(cfg),str(folder/'D.jpg'))
                # Malformed order file fails closed to no explicit
                # order (alphabetical), never raises.
                order_path.write_text('not json')
                bg.unlink();bg.symlink_to(folder/'B.jpg')
                self.assertEqual(module.next_artwork(cfg),str(folder/'C.jpg'))
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

    def test_ignored_wallpapers(self):
        # Direct ask: "in the tab dropdown i wanna add a feature for
        # ignore or like to make it not in rotation" -- excluded from
        # BOTH sequential and shuffle's candidate pool entirely, same
        # shared-state-file precedent as the order file (plain
        # filenames, no IPC round-trip, written directly by the
        # Wallpaper Shuffle extension's own Tab -> Ignore action).
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_ignored',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                for name in ['A.jpg','B.jpg','C.jpg']: (folder/name).write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                Path(home,'.local/state/omarchy/current/background').parent.mkdir(parents=True)
                ignored_path=Path(home)/'.local/state/ruixen/wallpaper-ignored.json'
                ignored_path.write_text(json.dumps({'version':1,'ignored':['A.jpg']}))
                self.assertEqual(module.next_artwork(cfg),str(folder/'B.jpg'))
                shuffled=module.configure(dict(shuffle=True))
                for _ in range(20):
                    self.assertIn(module.next_artwork(shuffled),[str(folder/'B.jpg'),str(folder/'C.jpg')])
                ignored_path.write_text(json.dumps({'version':1,'ignored':['A.jpg','B.jpg','C.jpg']}))
                with self.assertRaises(ValueError):
                    module.next_artwork(cfg)
                # Malformed ignored file fails closed to nothing ignored,
                # never raises.
                ignored_path.write_text('not json')
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.jpg'))
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

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
                # D.gif (video/GIF are real rotation candidates now, not
                # excluded -- see next_artwork's own comment) sorts after
                # C.png, same A/B/C/D naming as the other three.
                for name in ['A.JPG','B.webp','C.png','D.gif']: (folder/name).write_bytes(b'fixture')
                (folder/'subfolder').mkdir();(folder/'subfolder/ignored.png').touch()
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                self.assertEqual(module.load(),cfg)
                current=Path(home)/'.local/state/omarchy/current/background';current.parent.mkdir(parents=True)
                self.assertEqual(module.next_artwork(cfg),str(folder/'A.JPG'))
                current.symlink_to(folder/'B.webp')
                self.assertEqual(module.next_artwork(cfg),str(folder/'C.png'))
                current.unlink();current.symlink_to(folder/'C.png')
                self.assertEqual(module.next_artwork(cfg),str(folder/'D.gif'))
                shuffled=module.configure(dict(shuffle=True))
                self.assertTrue(module.load()['shuffle'])
                for _ in range(30):
                    self.assertIn(module.next_artwork(shuffled),[str(folder/'A.JPG'),str(folder/'B.webp'),str(folder/'D.gif')])
                (folder/'A.JPG').unlink(); (folder/'B.webp').unlink()
                self.assertEqual(module.next_artwork(shuffled),str(folder/'D.gif'))
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
