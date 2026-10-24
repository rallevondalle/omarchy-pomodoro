import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Fullscreen break screen, one per monitor, shown during breaks when the
// service asks for it (deep mode by default). It takes the keyboard so the
// break is a real break: L locks the session for leaving the desk, holding
// Esc for two seconds skips the break. When the break runs out the screen
// stays up and counts the overtime: Enter/Space starts the next focus, Esc
// does too with autoRestart (the default), otherwise it only closes it. The background fades from the theme to black over a minute.
// The real lock can't host this: a session lock hides every other surface
// and blanks the display.
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
    readonly property bool overtime: !!root.timer && root.timer.overtime
    property double escHeldSince: 0
    property real escProgress: 0
    property real dim: 0              // 0 = theme background, 1 = black

    NumberAnimation {
      id: dimAnim
      target: win
      property: "dim"
      from: 0
      to: 1
      duration: 60000
      easing.type: Easing.InOutSine
    }

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(Color.background.r * (1 - win.dim), Color.background.g * (1 - win.dim),
        Color.background.b * (1 - win.dim), 0.985 + 0.015 * win.dim)
    }

    // Swallow clicks so the desktop underneath can't be used.
    MouseArea { anchors.fill: parent; hoverEnabled: true }

    Item {
      id: keys
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (win.overtime && !event.isAutoRepeat
            && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
          root.timer.toggle()
        } else if (win.overtime && event.key === Qt.Key_Escape) {
          if (!event.isAutoRepeat) root.timer.dismissBreakScreen()
        } else if (event.key === Qt.Key_Escape) {
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

    onVisibleChanged: {
      if (visible) {
        escHeldSince = 0
        escProgress = 0
        dim = 0
        dimAnim.restart()
        keys.forceActiveFocus()
      } else {
        dimAnim.stop()
      }
    }

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
        text: !root.timer ? ""
          : (win.overtime ? "Pausen er slut · over tiden"
             : root.timer.phaseLabel + " · " + root.timer.modeLabel).toUpperCase()
        color: win.accent
        font.family: win.fontFamily
        font.pixelSize: 22
        font.bold: true
        font.letterSpacing: 4
      }

      // Calm clock: no motion, each character just dissolves slowly into the
      // next. Seconds are toned down so the minutes carry the screen and the
      // per-second change doesn't pull at the eye.
      Row {
        id: clock
        anchors.horizontalCenter: parent.horizontalCenter
        readonly property string value: !root.timer ? ""
          : (win.overtime ? root.timer.overtimeText : root.timer.remainingText)
        readonly property int pixelSize: Math.min(220, win.height * 0.22)
        readonly property int colonIndex: value.indexOf(":")

        TextMetrics {
          id: digitMetrics
          font.family: win.fontFamily
          font.pixelSize: clock.pixelSize
          font.bold: true
          text: "0"
        }

        Repeater {
          model: clock.value.length

          Item {
            id: slot
            required property int index
            readonly property string ch: clock.value.charAt(index)
            readonly property real tone: index > clock.colonIndex && clock.colonIndex >= 0 ? 0.4
              : (ch === ":" || ch === "+" ? 0.55 : 1)
            property string shown: ch
            property string previous: ""
            property real t: 1

            width: /[0-9]/.test(ch) ? digitMetrics.advanceWidth : glyph.implicitWidth
            height: glyph.implicitHeight

            onChChanged: {
              if (ch === shown) return
              previous = shown
              shown = ch
              fade.restart()
            }

            NumberAnimation {
              id: fade
              target: slot
              property: "t"
              from: 0
              to: 1
              duration: 900
              easing.type: Easing.InOutSine
            }

            Text {
              id: glyph
              anchors.centerIn: parent
              opacity: slot.tone * slot.t
              text: slot.shown
              color: win.fg
              font.family: win.fontFamily
              font.pixelSize: clock.pixelSize
              font.bold: true
            }

            Text {
              anchors.centerIn: parent
              opacity: slot.tone * (1 - slot.t)
              visible: slot.t < 1
              text: slot.previous
              color: win.fg
              font.family: win.fontFamily
              font.pixelSize: clock.pixelSize
              font.bold: true
            }
          }
        }
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: !root.timer ? ""
          : (win.overtime ? "Tag den tid du har brug for. Klar til runde " + root.timer.round + "?"
             : root.timer.breakTip)
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
          visible: win.overtime && !!root.timer && !root.timer.autoRestart
          text: "Enter  start runde " + (root.timer ? root.timer.round : "")
          color: win.accent
          font.family: win.fontFamily
          font.pixelSize: 15
        }

        Text {
          text: !win.overtime ? "hold Esc  spring pausen over"
            : (root.timer && root.timer.autoRestart ? "Esc  start runde " + root.timer.round : "Esc  luk pauseskærmen")
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
