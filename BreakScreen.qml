import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Fullscreen break screen, one per monitor, shown during breaks when the
// service asks for it (deep mode by default). It takes the keyboard so the
// break is a real break: L locks the session for leaving the desk, holding
// Esc for two seconds skips the break. It disappears by itself when the
// break ends. The real lock can't host this: a session lock hides every
// other surface and blanks the display.
Variants {
  id: root

  property var timer: null
  model: Quickshell.screens

  PanelWindow {
    id: win
    required property var modelData
    screen: modelData

    visible: !!root.timer && root.timer.breakScreenActive
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.namespace: "pomodoro-break"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property color fg: Color.foreground
    readonly property color accent: Color.accent
    readonly property color muted: Qt.darker(Color.foreground, 1.6)
    readonly property string fontFamily: Style.font.family
    property double escHeldSince: 0
    property real escProgress: 0

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.985)
    }

    // Swallow clicks so the desktop underneath can't be used.
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (!event.isAutoRepeat) win.escHeldSince = Date.now()
        } else if (event.key === Qt.Key_L && !event.isAutoRepeat) {
          Quickshell.execDetached(["omarchy-system-lock"])
        }
        event.accepted = true
      }
      Keys.onReleased: function(event) {
        if (event.key === Qt.Key_Escape && !event.isAutoRepeat) {
          win.escHeldSince = 0
          win.escProgress = 0
        }
        event.accepted = true
      }
    }

    onVisibleChanged: if (visible) { escHeldSince = 0; escProgress = 0; keys.forceActiveFocus() }

    Timer {
      interval: 50
      repeat: true
      running: win.visible && win.escHeldSince > 0
      onTriggered: {
        win.escProgress = Math.min(1, (Date.now() - win.escHeldSince) / 2000)
        if (win.escProgress >= 1) {
          win.escHeldSince = 0
          win.escProgress = 0
          root.timer.skip()
        }
      }
    }

    Column {
      anchors.centerIn: parent
      spacing: 18
      width: Math.min(parent.width - 80, 900)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.timer ? (root.timer.phaseLabel + " · " + root.timer.modeLabel).toUpperCase() : ""
        color: win.accent
        font.family: win.fontFamily
        font.pixelSize: 22
        font.bold: true
        font.letterSpacing: 4
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.timer ? root.timer.remainingText : ""
        color: win.fg
        font.family: win.fontFamily
        font.pixelSize: Math.min(220, win.height * 0.22)
        font.bold: true
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.timer ? root.timer.breakTip : ""
        color: win.fg
        opacity: 0.8
        font.family: win.fontFamily
        font.pixelSize: 20
      }

      Item { width: 1; height: 40 }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 48

        Text {
          text: "L  lås skærmen"
          color: win.muted
          font.family: win.fontFamily
          font.pixelSize: 15
        }

        Text {
          text: "hold Esc  spring pausen over"
          color: win.escProgress > 0 ? win.accent : win.muted
          font.family: win.fontFamily
          font.pixelSize: 15
        }
      }

      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 260
        height: 3
        radius: 2
        color: Qt.rgba(win.fg.r, win.fg.g, win.fg.b, 0.12)
        opacity: win.escProgress > 0 ? 1 : 0

        Rectangle {
          width: parent.width * win.escProgress
          height: parent.height
          radius: 2
          color: win.accent
        }
      }
    }
  }
}
