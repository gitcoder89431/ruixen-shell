# Fake third-party bar-widget fixtures

Four minimal, real `bar-widget`-kind Omarchy plugins, deliberately kept
outside the `ruixen.*` id namespace (`test.thirdparty.*`), so tests can
prove Ruixen's bar hosts genuinely arbitrary third-party widgets rather
than only ones it happens to recognize by id.

Added for "[P1] Support arbitrary third-party widgets in the horizontal
center region" (#27), per that issue's own recommendation to build
these once and reuse them across #27, #28, and #29 -- a stable
compatibility gate for future `ruixen.bar/Bar.qml` changes, rather than
throwaway fixtures each issue reinvents.

- `test.thirdparty.left` -- fixed 40px width, plain box. A minimal
  baseline fixture for the left region.
- `test.thirdparty.center-a` -- fixed 60px width, and reads an inline
  `label` setting (`settings: { "label": "..." }` in shell.json) to
  prove per-widget inline settings really do pass through unchanged.
- `test.thirdparty.center-b` -- fixed 100px width, deliberately
  DIFFERENT from every other fixture here, to prove the host doesn't
  assume a uniform widget size anywhere.
- `test.thirdparty.right` -- fixed 40px width, plain box, for the
  right region.
- `test.thirdparty.tall` -- 40x48px, deliberately TALLER than
  `ruixen.bar`'s own `barSize` (34). Added for #29: every other fixture
  here is a uniform 24px tall, which centers inside a 34px row with no
  slack either way and can't expose a vertical-centering bug on its
  own.

Never deployed by `install.sh` (its own plugin-copy glob is
`ruixen.*/`, these deliberately fall outside it) and never referenced
by the real canonical `lib/ruixen-bar-canonical.json` layout -- purely
test-time fixtures, copied into a throwaway fake `$HOME`'s own
`~/.config/omarchy/plugins/` by whichever test needs them.
