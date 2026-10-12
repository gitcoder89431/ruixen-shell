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
# Wallpaper appearance now lives only in the launcher's Wallpapers
# extension -- the notch picker dropped it in favor of Artwork rotation
# only, so there's no second packaged copy left to keep in sync against.
HELPERS = [ROOT / 'ruixen.launcher/extensions/wallpapers/wallpaper-effects.py']
VALID = dict(transitionEffect='pixel-dissolve', transitionDurationMs=8000, transitionSoftness=.12, ambientZoom=True, ambientGlow=True, disableMotion=False)

class SettingsTests(unittest.TestCase):
    def test_packaged_assets_stay_in_sync(self):
        folders=[ROOT/'ruixen.background',ROOT/'ruixen.launcher/extensions/wallpapers']
        for asset in ['WallpaperGlitch.qml','WallpaperAmbient.qml','WallpaperTransitionMask.qml','GLITCH-LICENSE.txt','shaders/glitch.frag','shaders/glitch.frag.qsb','shaders/ambient.frag','shaders/ambient.frag.qsb']:
            expected=(folders[0]/asset).read_bytes()
            for folder in folders[1:]:
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
