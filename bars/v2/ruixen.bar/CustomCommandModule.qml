import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

// User-defined shell-command bar module (exec/interval/click handlers).
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component CustomCommandModule: WidgetButton { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at this component's one instantiation site (inside
// ModuleSlot.qml, itself forwarding its own received barRoot down). Note
// `bar: barRoot` below (was `bar: root`) -- this widget sets its own
// inherited `bar` property directly to the bar root rather than a scoped
// PluginBarFacade the way ModuleSlot's injectProps() does for registered/
// custom-QML widgets; that's pre-existing behavior, unchanged by this
// move. No behavior change from this move.
WidgetButton {
  id: customRoot

  required property Item barRoot
  required property var entry
  readonly property string moduleName: customRoot.barRoot.entryId(entry)
  readonly property var settings: customRoot.barRoot.entrySettings(entry)
  property string outputText: ""
  property string outputTooltip: ""
  property bool outputActive: false

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function update(raw) {
    var data = Util.parseModuleJson(raw)
    var klass = data.class || data.alt || ""

    outputText = data.text || String(raw || "").trim()
    outputTooltip = data.tooltip || String(setting("tooltip", ""))
    outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
  }

  bar: customRoot.barRoot
  text: outputText || String(setting("text", ""))
  tooltipText: outputTooltip || String(setting("tooltip", ""))
  active: outputActive
  keepSpace: setting("keepSpace", false) === true
  horizontalMargin: Number(setting("horizontalMargin", 7.5))
  verticalPadding: Number(setting("verticalPadding", 6))
  fontSize: Number(setting("fontSize", 12))

  onPressed: function(button) {
    var command = ""
    if (button === Qt.RightButton)
      command = String(setting("onRightClick", ""))
    else if (button === Qt.MiddleButton)
      command = String(setting("onMiddleClick", ""))
    else
      command = String(setting("onClick", ""))

    if (command) customRoot.barRoot.run(command)
  }

  Process {
    id: customProc
    command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: customRoot.update(text)
    }
  }

  Timer {
    interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
    running: String(customRoot.setting("exec", "")) !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: customRoot.barRoot.runProcess(customProc)
  }
}
