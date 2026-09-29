// ModuleList bound to region "right".
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component RightModules: ModuleList { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot
// comes from ModuleList's own already-required property (this type
// extends ModuleList, so re-declaring it here would conflict) -- set at
// this component's own instantiation site.
ModuleList {
  entries: barRoot.layoutEntries("right")
  region: "right"
}
