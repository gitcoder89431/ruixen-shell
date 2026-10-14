#!/usr/bin/env python3
"""Exercise the production settings writer in an isolated home directory."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import subprocess

ROOT = Path(__file__).resolve().parents[1]
# Issue #105: wallpaper-effects.py used to be a hand-copied, byte-
# identical duplicate under both picker packages -- real backend logic
# (appearance-settings validation, the renderer enable/disable
# lifecycle), not a rendering asset, so it's now a single real file
# under ruixen.wallpaper/, deployed into both picker packages at
# install time by install.sh's own inject_shared_wallpaper_files (see
# that function's header comment, and tests/install-shared-wallpaper-
# files.sh, which proves the deploy side against the real install.sh).
# This test only needs to exercise the one real copy's own behavior --
# a second, third deployed copy is guaranteed byte-identical by
# construction (a plain `cp`), not by independently re-implementing the
# same logic twice, so there is nothing left to parity-test for it here.
#
# The notch picker's own compact Transition chip (WallpaperAppearanceState
# .qml) carries its own copy of the render/preview assets below, same
# three-way parity the shader/QML assets below have among ruixen.background
# and the launcher. The notch's wallpaper grid ALSO doubles as a live
# transition preview surface now (hover a tile, see it play) -- the same
# preview wrapper and shader primitives ruixen.launcher's Wallpapers
# extension uses, so the notch needs that asset set too, not just the
# renderer-only subset it carried before. Those remain genuinely
# duplicated UI/render assets (packaging requires each surface to carry
# its own), unlike wallpaper-effects.py above.
HELPERS = [ROOT / 'ruixen.wallpaper/wallpaper-effects.py']
VALID = dict(transitionEffect='pixel-dissolve', transitionDurationMs=8000, transitionSoftness=.12, ambientZoom=True, ambientGlow=True, disableMotion=False)

class SettingsTests(unittest.TestCase):
    def test_packaged_assets_stay_in_sync(self):
        folders=[ROOT/'ruixen.background',ROOT/'ruixen.launcher/extensions/wallpapers',ROOT/'bars/widgets/ruixen.notch']
        for asset in ['WallpaperGlitch.qml','WallpaperAmbient.qml','WallpaperTransitionMask.qml','GLITCH-LICENSE.txt','shaders/glitch.frag','shaders/glitch.frag.qsb','shaders/ambient.frag','shaders/ambient.frag.qsb']:
            expected=(folders[0]/asset).read_bytes()
            for folder in folders[1:]:
                self.assertEqual((folder/asset).read_bytes(),expected, str(folder/asset))
        # WallpaperEffectPreview.qml and WallpaperEffectModel.js only
        # exist where something actually hosts a live hover preview --
        # ruixen.background is the real renderer, not a preview host,
        # so it has no copy of either and sits out of this check.
        preview_folders=[ROOT/'ruixen.launcher/extensions/wallpapers',ROOT/'bars/widgets/ruixen.notch']
        for asset in ['WallpaperEffectPreview.qml','WallpaperEffectModel.js']:
            expected=(preview_folders[0]/asset).read_bytes()
            for folder in preview_folders[1:]:
                self.assertEqual((folder/asset).read_bytes(),expected, str(folder/asset))

    def test_writers(self):
        for helper in HELPERS:
            with self.subTest(helper=helper), tempfile.TemporaryDirectory() as home:
                previous = os.environ.get('HOME')
                os.environ['HOME'] = home
                try:
                    spec = importlib.util.spec_from_file_location('effects', helper)
                    module = importlib.util.module_from_spec(spec)
                    spec.loader.exec_module(module)
                    path = Path(home) / '.local/state/ruixen/wallpaper-appearance.json'
                    path.parent.mkdir(parents=True)
                    path.write_text(json.dumps({'unrelated': 'keep'}))
                    module.save(VALID)
                    self.assertEqual(json.loads(path.read_text()), dict(VALID, version=1, unrelated='keep'))
                    for effect in ['reveal','bleed','pixel-dissolve','iris','shutters','scanline','ink-spread','aurora','vortex','signal-tear','datamosh','vhs','code-bleed']:
                        module.save(dict(VALID, transitionEffect=effect))
                        self.assertEqual(json.loads(path.read_text())['transitionEffect'], effect)
                    for background in ['none','crt','matrix']:
                        module.save(dict(VALID, backgroundEffect=background, backgroundIntensity=.4, backgroundSpeed=1.5))
                        self.assertEqual(json.loads(path.read_text())['backgroundEffect'], background)
                    # Old GUI snapshots preserve independent background settings.
                    module.save(VALID)
                    self.assertEqual(json.loads(path.read_text())['backgroundEffect'], 'matrix')
                    for effect in ['signal-tear','datamosh','vhs','code-bleed']:
                        module.save(dict(VALID, transitionOptions={effect:dict(strength=.3,density=1.7)}))
                        self.assertEqual(json.loads(path.read_text())['transitionOptions'][effect]['density'],1.7)
                    with self.assertRaises(ValueError): module.save([])
                    before = path.read_bytes()
                    for key, value in [('version', 2), ('version', True), ('transitionEffect', 'invalid'), ('transitionDurationMs', -1), ('transitionDurationMs', True), ('transitionSoftness', float('nan')), ('ambientZoom', 'on'), ('backgroundEffect', 'bogus'), ('backgroundIntensity', True), ('backgroundIntensity', 2), ('backgroundSpeed', 0), ('backgroundSpeed', float('nan')), ('transitionOptions', []), ('transitionOptions', {'bogus':{}}), ('transitionOptions', {'vhs':{'density':0}}), ('transitionOptions', {'vhs':{'strength':True}})]:
                        with self.assertRaises(ValueError):
                            module.save(dict(VALID, **{key: value}))
                        self.assertEqual(path.read_bytes(), before)
                    # Enabling refuses a second active clone without changing config.
                    manifest=Path(home)/'.config/omarchy/plugins/ruixen.background/manifest.json'
                    manifest.parent.mkdir(parents=True);manifest.write_text('{}')
                    foreign=manifest.parent.parent/'someone.background/manifest.json'
                    foreign.parent.mkdir();foreign.write_text(json.dumps({'omarchy':{'clonedFrom':'omarchy.background'}}))
                    plugins=json.dumps([{'id':'someone.background','enabled':True}])
                    result=subprocess.CompletedProcess([],0,stdout=plugins)
                    with patch.object(module.subprocess,'run',return_value=result) as run:
                        with self.assertRaisesRegex(ValueError,'Disable someone.background'):
                            module.enable_renderer()
                        self.assertEqual(run.call_count,1)
                    self.assertEqual(path.read_bytes(),before)
                    # A malformed file remains intact and its controls report the error.
                    path.write_text(json.dumps(dict(VALID,version=2)))
                    future=path.read_bytes()
                    with self.assertRaises(ValueError):module.save(VALID)
                    self.assertEqual(path.read_bytes(),future)
                    path.write_text('{broken')
                    unavailable=subprocess.CompletedProcess([],1,stdout='')
                    with patch.object(module.subprocess,'run',return_value=unavailable):
                        state=module.renderer_status()
                        self.assertTrue(state['installed'])
                        self.assertIn('Unable to read appearance settings',state['error'])
                    self.assertEqual(path.read_text(),'{broken')
                    self.assertEqual(list(path.parent.glob('.ambient-wallpaper-*')), [])
                finally:
                    if previous is None:
                        os.environ.pop('HOME', None)
                    else:
                        os.environ['HOME'] = previous

if __name__ == '__main__':
    unittest.main()
