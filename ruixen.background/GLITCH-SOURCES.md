# Glitch source attribution

Upstream: https://github.com/DasPoxy/Glitch-Launcher-Collection
Revision: d5443cdc1a156a2a8cefadda6381630c073009bd

- `shaders/glitch.frag`: adapted from `glitch-background-selector/shaders/glitch.frag`.
  Changes: exact wallpaper endpoints, distortion strength, and effect density.
- `shaders/ambient.frag`: independent transparent overlay using the per-column
  rain head/trail formula from upstream `shaders/preview.frag`; procedural binary
  glyphs replace the font atlas. CRT texture is static.
- QML wrappers and GUI controls are local integration code.

MIT license notices are retained in GLITCH-LICENSE.txt. Compiled Qt shader files
are generated from the accompanying GLSL source using Qt 6 qsb.
