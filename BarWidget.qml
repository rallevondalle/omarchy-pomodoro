import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Bar face for the shared timer service, and host for the dropdown panel.
// left = start/pause/resume · right = panel · middle = skip · scroll = ±1 min
BarWidget {
  id: root
  moduleName: "rassta.pomodoro"

  readonly property var timer: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool stopped: !timer || timer.stopped
  readonly property bool ready: !!timer && timer.ready
  readonly property string icon: timer && timer.onBreak ? "󰅶" : "󱎫"
  readonly property string label: {
    if (stopped || vertical) return icon
    if (ready) return icon + " start"
    return icon + " " + (timer.countingUp ? "↑" : "") + timer.remainingText
  }

  function syncConfig() {
    if (timer && typeof timer.configure === "function") timer.configure(settings)
    injectPanel()
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Style.bar.iconCanvas

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.timer = root.timer
  }

  onBarChanged: injectPanel()
  onTimerChanged: Qt.callLater(syncConfig)
  onSettingsChanged: Qt.callLater(syncConfig)
  Component.onCompleted: Qt.callLater(syncConfig)

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.label
    active: root.ready
    dimmed: root.stopped || root.timer.paused
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: {
      if (root.opened) return ""
      var help = "\nVenstre: start/pause · Højre: menu · Midt: spring over · Scroll: ±1 min"
      if (!root.timer) return "Pomodoro"
      var t = root.timer
      if (t.stopped) return "Pomodoro · " + t.modeLabel + " — klik for at starte" + help
      if (t.ready) return "Pausen er slut — klik for at starte runde " + t.round + help
      return t.phaseLabel + " · " + t.modeLabel + " · runde " + t.round
        + (t.paused ? " (sat på pause)" : "") + " · " + t.remainingText + help
    }

    onPressed: function(b) {
      if (!root.timer) return
      if (b === Qt.RightButton) root.toggle()
      else if (b === Qt.MiddleButton) root.timer.skip()
      else root.timer.toggle()
    }
    onWheelMoved: function(delta) {
      if (root.timer) root.timer.adjust(delta > 0 ? 1 : -1)
    }
  }
}
