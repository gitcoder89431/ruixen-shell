import QtQuick
import QtQuick.Effects

// Floating-pill background shared by each module group. The actual color
// comes from the root surface resolver (via barRoot below) so future
// Theme/Glass work changes the token once instead of cloning literals
// into every pill.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 2) as a pure file
// move: this was previously `component GroupPill: Rectangle { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at each of this component's instantiation sites
// (`barRoot: root`). No behavior change from this move.
Rectangle {
  id: pillRoot

  required property Item barRoot

  radius: height / 2
  color: pillRoot.barRoot.floatingPillFill
  // Without this, a full circle (radius === width/2 === height/2, like
  // the solo menu pill) renders as a faceted octagon instead of a
  // smooth curve — much more visible than on a stadium shape (most of
  // that outline is straight, only the two end-caps curve).
  antialiasing: true

  // Direct follow-up after the settings card's own shadow ("try the
  // pill next then") -- every floating pill in the bar shares this
  // one component, so adding it here covers all of them uniformly.
  // Lower risk than ruixen.notch's own attempt (reverted, see that
  // file's own comment): GroupPill is a plain Rectangle with no
  // existing mask/effect stacking to interact with, unlike notchBg's
  // own MultiEffect which was already doing custom silhouette
  // masking before shadow properties were added to it.
  //
  // Tighter and darker than the first pass -- direct correction ("the
  // draw is too far, it looks like faded, gotta closer and darker"):
  // blur 0.3 -> 0.15 and offset 3 -> 1 pull the shadow in close to
  // the pill's own edge instead of spreading/softening it into a
  // faded halo; opacity 0.6 -> 0.8 makes it read as a real shadow
  // rather than a faint tint.
  //
  // Bumped again (0.15/1 -> 0.35/3) per direct follow-up once both
  // Solid and Glass surface materials landed (#78): at the tight,
  // low-blur/low-offset settings above the shadow read as barely
  // there, especially under Glass's own semi-transparent fill --
  // "can you add a drop shadow to it so it looks a bit raised from
  // the bg" (asked as if there were none at all).
  //
  // 0.35/3 overshot -- direct live correction ("thats a bit too far,
  // is there a little bit tighter shadow but not as tight as
  // before"): landed on 0.24/2, the midpoint between the original
  // barely-there pass and the overshot one.
  //
  // shadowColor itself is already pure black (barRoot.surfaceShadow) --
  // opacity 0.8 blended with the blur is what read as "greyish/muted
  // black" rather than the color being wrong (direct live question:
  // "is the shadow black? i feel like it looks more greyish"). Bumped
  // to 0.95 so the shadow's own core reads solidly black instead of a
  // washed-out tint, blur/offset unchanged.
  layer.enabled: true
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: pillRoot.barRoot.surfaceShadow
    shadowOpacity: 0.95
    shadowBlur: 0.24
    shadowVerticalOffset: 2
  }
}
