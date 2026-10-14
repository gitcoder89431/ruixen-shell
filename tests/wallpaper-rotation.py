#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest

class RotationTests(unittest.TestCase):
    def test_qml_state_is_a_single_real_copy_now(self):
        # Issue #105: WallpaperRotationState.qml used to be a hand-
        # copied, byte-identical duplicate in three places (the notch's
        # single cycling pill, the launcher Wallpapers extension's own
        # Shuffle section, and the Wallpaper Shuffle extension's own
        # interval chip row) with nothing enforcing the copies stayed in
        # sync -- this test used to BE that enforcement, three-way
        # byte-identity. Now there is exactly one real, hand-maintained
        # copy (ruixen.wallpaper/), deployed into the other two plugins
        # at install time by install.sh's own
        # inject_shared_wallpaper_files -- proven against the real
        # install.sh in tests/install-shared-wallpaper-files.sh, not
        # re-proven here. What's left to guard here is that a future
        # edit doesn't silently reintroduce a hand-maintained duplicate
        # in this checkout.
        root = Path(__file__).resolve().parents[1]
        canonical = root / 'ruixen.wallpaper/WallpaperRotationState.qml'
        self.assertTrue(canonical.is_file())
        for stale in (
            root / 'bars/widgets/ruixen.notch/WallpaperRotationState.qml',
            root / 'ruixen.launcher/extensions/wallpapers/WallpaperRotationState.qml',
            root / 'ruixen.launcher/extensions/wallpaper-shuffle/WallpaperRotationState.qml',
        ):
            self.assertFalse(stale.is_file(), str(stale) + ' should not exist in the checkout any more')

    def test_theme_backgrounds_included(self):
        # Direct ask: "if i switch theme, the wallpapers that came
        # with the theme is included in the shuffle rotation right,
        # it doesnt skip those that comes with the theme right." It
        # did skip them -- reconciled_images() used to only ever scan
        # the single configured folder, with no knowledge of either
        # theme-background location list-wallpapers.sh's own "omarchy"
        # find pipeline already scans for the picker's display list.
        # Both locations covered here: the active-theme symlink
        # (.../current/theme/backgrounds) and the theme-name-keyed
        # directory (.../backgrounds/<theme>), plus a theme with
        # neither (no backgrounds shipped) failing closed instead of
        # raising.
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_theme',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                (folder/'Custom.jpg').write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                Path(home,'.local/state/omarchy/current/background').parent.mkdir(parents=True)
                # No theme.name / no theme backgrounds at all yet --
                # behaves exactly as before this feature, just the
                # configured folder.
                self.assertEqual(module.next_artwork(cfg),str(folder/'Custom.jpg'))
                active_theme_dir=Path(home)/'.local/state/omarchy/current/theme/backgrounds'
                active_theme_dir.mkdir(parents=True)
                (active_theme_dir/'ThemeActive.jpg').write_bytes(b'x')
                theme_name_file=Path(home)/'.local/state/omarchy/current/theme.name'
                theme_name_file.parent.mkdir(parents=True,exist_ok=True)
                theme_name_file.write_text('aurora')
                named_theme_dir=Path(home)/'.config/omarchy/backgrounds/aurora'
                named_theme_dir.mkdir(parents=True)
                (named_theme_dir/'ThemeNamed.jpg').write_bytes(b'x')
                images={Path(p).name for p in module.reconciled_images(cfg)}
                self.assertEqual(images,{'Custom.jpg','ThemeActive.jpg','ThemeNamed.jpg'})
                # A real pick can land on a theme wallpaper too, not
                # just ones from the configured folder.
                picks={Path(module.next_artwork(cfg)).name for _ in range(3)}
                self.assertTrue(picks.issubset({'Custom.jpg','ThemeActive.jpg','ThemeNamed.jpg'}))
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

    def test_rotation_state_never_forces_shuffle(self):
        # Direct correction once the Wallpaper Shuffle launcher
        # extension's own reorderable queue existed: "all that notch
        # thing will do is control the interval and off now, the
        # shuffle and rotation is managed with the list in wallpaper
        # shuffle only" -- cycleInterval()/turnOff()/selectInterval()
        # all used to hardcode shuffle:true on every write, silently
        # fighting the queue back into random mode. None of them should
        # mention shuffle at all any more -- configure()'s own
        # "preserves omitted settings" merge is what leaves it alone.
        root = Path(__file__).resolve().parents[1]
        qml = (root / 'ruixen.wallpaper/WallpaperRotationState.qml').read_text()
        code_lines = [line for line in qml.splitlines() if not line.strip().startswith('//')]
        code = '\n'.join(code_lines)
        self.assertEqual(code.count('shuffle: true'), 0)
        self.assertEqual(code.count('shuffle:true'), 0)

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
                # Expects C.jpg, not D -- next_artwork's own live-queue
                # rotation (see its header comment) already moved B
                # ahead of C after the previous call, so advancing from
                # B now lands on C; D (brand new, appended to the very
                # end of the reconciled order) isn't reachable until
                # the cycle comes back around.
                (folder/'D.jpg').write_bytes(b'x')
                bg.unlink();bg.symlink_to(folder/'B.jpg')
                self.assertEqual(module.next_artwork(cfg),str(folder/'C.jpg'))
                # Malformed order file fails closed to no explicit
                # order (alphabetical), never raises.
                order_path.write_text('not json')
                bg.unlink();bg.symlink_to(folder/'B.jpg')
                self.assertEqual(module.next_artwork(cfg),str(folder/'C.jpg'))
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

    def test_live_queue_rotation(self):
        # Direct ask: "make this left panel list live so current is
        # ontop, when it rotates it goes to the buttom... like a live
        # que". Sequential mode only (shuffle's own random.choice has
        # no stable position to rotate around) -- next_artwork persists
        # a cyclic rotation of the WHOLE order so the item it just
        # picked sits at the front and the one that was current retires
        # to the back, with everyone else keeping relative order.
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_queue',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                for name in ['A.jpg','B.jpg','C.jpg','D.jpg']: (folder/name).write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                bg=Path(home)/'.local/state/omarchy/current/background';bg.parent.mkdir(parents=True)
                module.next_artwork(cfg)
                self.assertEqual(module.load_order(),['A.jpg','B.jpg','C.jpg','D.jpg'])
                bg.symlink_to(folder/'A.jpg')
                picked=Path(module.next_artwork(cfg)).name
                self.assertEqual(picked,'B.jpg')
                # B (the new pick) is at the front; A (just retired)
                # is at the very back; C/D keep their relative order.
                self.assertEqual(module.load_order(),['B.jpg','C.jpg','D.jpg','A.jpg'])
                bg.unlink();bg.symlink_to(folder/'B.jpg')
                picked=Path(module.next_artwork(cfg)).name
                self.assertEqual(picked,'C.jpg')
                self.assertEqual(module.load_order(),['C.jpg','D.jpg','A.jpg','B.jpg'])
                # Shuffle mode never rotates the persisted order -- it
                # has no stable position to rotate around.
                shuffled=module.configure(dict(shuffle=True))
                for _ in range(10): module.next_artwork(shuffled)
                self.assertEqual(module.load_order(),['C.jpg','D.jpg','A.jpg','B.jpg'])
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

    def test_manual_pick_rotates_queue(self):
        # Direct ask: "if i manually select something as the wallpaper,
        # then the live que breaks?" -- it did: applySelected()/select()
        # only ever flipped currentBackground, never touched the
        # persisted order, so the queue stayed stale until rotation's
        # own timer happened to fire again (or never, if it was off).
        # rotate_to() (wired to the mark-current CLI action, called by
        # every manual-pick call site right alongside its own apply
        # IPC) runs the exact same round-robin next_artwork() does for
        # its own pick, just anchored on a given name instead of
        # reading current/background.
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_manual',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                for name in ['A.jpg','B.jpg','C.jpg','D.jpg']: (folder/name).write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                self.assertEqual(module.load_order(),[])
                # Jumping straight to D (never picked by rotation at all)
                # still rotates D to the front, C/A/B keeping their
                # existing relative order behind it.
                module.rotate_to('D.jpg',cfg)
                self.assertEqual(module.load_order(),['D.jpg','A.jpg','B.jpg','C.jpg'])
                # A later real rotation continues sequentially from
                # wherever the manual pick left the queue, exactly as if
                # D had been reached by rotation itself.
                bg=Path(home)/'.local/state/omarchy/current/background';bg.parent.mkdir(parents=True)
                bg.symlink_to(folder/'D.jpg')
                picked=Path(module.next_artwork(cfg)).name
                self.assertEqual(picked,'A.jpg')
                self.assertEqual(module.load_order(),['A.jpg','B.jpg','C.jpg','D.jpg'])
                # Unknown name (outside the folder, or already ignored
                # out of the pool) is a silent no-op, not an error.
                module.rotate_to('nonexistent.jpg',cfg)
                self.assertEqual(module.load_order(),['A.jpg','B.jpg','C.jpg','D.jpg'])
                # Shuffle has no stable position to rotate around, same
                # reasoning as next_artwork's own shuffle branch.
                shuffled=module.configure(dict(shuffle=True))
                module.rotate_to('C.jpg',shuffled)
                self.assertEqual(module.load_order(),['A.jpg','B.jpg','C.jpg','D.jpg'])
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
                # never raises. Expects B.jpg, not A -- the earlier call
                # already rotated the persisted order to [B, C] (A was
                # ignored at the time and never entered it), and A only
                # rejoins at the back once it's reconciled back in here;
                # current was never set in this test, so this still
                # starts from the front of whatever's reconciled.
                ignored_path.write_text('not json')
                self.assertEqual(module.next_artwork(cfg),str(folder/'B.jpg'))
            finally:
                if old is None:os.environ.pop('HOME',None)
                else:os.environ['HOME']=old

    def test_next_artwork_advances_past_a_video_current(self):
        # Direct live report: "i just wait 5 min but the wallpaper didnt
        # change, i think the interval shuffle is broken" -- confirmed
        # live, reproducible: with a video/GIF actually active,
        # next_artwork() kept returning the SAME first item in the
        # queue forever, both via the real IPC call and this exact
        # helper invoked standalone. Root cause: $HOME/.local/state/
        # omarchy/current/background never resolves to a video/GIF's
        # own raw path -- ruixen.wallpaper/Service.qml's own play()/
        # playGif() always retarget it at a generated POSTER jpg
        # instead (md5(raw path) under ~/.cache/ruixen/wallpaper-
        # posters/, issue #66's own fix for an ImageMagick memory
        # blowup). Every OTHER test in this file symlinks current/
        # background directly to a raw file in the scanned folder,
        # which never exercises this -- only a real video/GIF, made
        # current through its own poster indirection exactly like
        # production actually does it, reproduces the bug (and would
        # have caught it before it ever reached a real session).
        helper=Path(__file__).resolve().parents[1]/'ruixen.wallpaper/wallpaper-rotation.py'
        spec=importlib.util.spec_from_file_location('rotation_video_current',helper)
        module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as home:
            old=os.environ.get('HOME');os.environ['HOME']=home
            try:
                folder=Path(home)/'art';folder.mkdir()
                for name in ['A.mp4','B.mp4','C.mp4']: (folder/name).write_bytes(b'x')
                cfg=module.configure(dict(enabled=True,folder=str(folder),intervalMinutes=15))
                bg=Path(home)/'.local/state/omarchy/current/background';bg.parent.mkdir(parents=True)
                poster_dir=Path(home)/'.cache/ruixen/wallpaper-posters';poster_dir.mkdir(parents=True)
                def point_bg_at(name):
                    real=str(folder/name)
                    poster=poster_dir/(module.current_identity(real).rsplit('/',1)[-1])
                    poster.write_bytes(b'poster')
                    if bg.exists() or bg.is_symlink(): bg.unlink()
                    bg.symlink_to(poster)
                # A.mp4 is current (via its own poster, not its raw path
                # -- the real production shape) -- advances to B, not
                # back to A.
                point_bg_at('A.mp4')
                picked=Path(module.next_artwork(cfg)).name
                self.assertEqual(picked,'B.mp4')
                self.assertEqual(module.load_order(),['B.mp4','C.mp4','A.mp4'])
                # Confirmed the fix, not just a one-off: advances again
                # from B to C the same way.
                point_bg_at('B.mp4')
                picked=Path(module.next_artwork(cfg)).name
                self.assertEqual(picked,'C.mp4')
                self.assertEqual(module.load_order(),['C.mp4','A.mp4','B.mp4'])
                # Shuffle mode's own "don't immediately repeat" exclusion
                # has the identical comparison -- same fix, same video-
                # as-current setup, asserted over enough draws that a
                # real bug (current never excluded) would show up.
                point_bg_at('C.mp4')
                shuffled=module.configure(dict(shuffle=True))
                for _ in range(20):
                    self.assertIn(Path(module.next_artwork(shuffled)).name,['A.mp4','B.mp4'])
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
