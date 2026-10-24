import QtQuick
import qs.Commons
import qs.Ui

// Dropdown under the bar timer: status header plus up to ten actions on the
// number keys (1–9, 0), and a settings view (s) for the lunch length and
// which actions are shown. Arrows/jk + Enter also work; Esc goes back/closes.
Panel {
  id: root
  moduleName: "rallevondalle.pomodoro"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var timer: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color muted: Qt.darker(foreground, 1.6)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int selected: 0
  property bool settingsView: false

  function glyph(code) { return String.fromCodePoint(code) }

  readonly property string toggleLabel: !timer || timer.stopped ? "Start fokus"
    : timer.ready ? "Start runde " + timer.round
    : timer.paused ? "Fortsæt" : "Sæt på pause"
  readonly property int toggleIcon: !timer || timer.stopped || timer.ready || timer.paused ? 0xF040A : 0xF03E4
  readonly property int lunchMinutes: timer ? timer.lunchMinutes : 45
  readonly property var hiddenItems: timer ? timer.hiddenItems : []

  // Every action the panel knows. `key` is its fixed number in the settings
  // view; the main view numbers the visible ones 1..9, 0 in order.
  readonly property var allActions: [
    { id: "toggle", group: "", icon: toggleIcon, label: toggleLabel, menuLabel: "Start / pause", hint: "", run: function() { timer.toggle() } },
    { id: "classic", group: "Fokus", icon: 0xF13AB, label: "Klassisk " + (timer ? timer.config.work + "/" + timer.config.shortBreak : "25/5"),
      hint: "standard", mode: "classic", run: function() { timer.startFocus("classic") } },
    { id: "deep", group: "Fokus", icon: 0xF13AB, label: "Dyb 50/10", hint: "krævende", mode: "deep", run: function() { timer.startFocus("deep") } },
    { id: "flow", group: "Fokus", icon: 0xF13AB, label: "Flow", hint: "pause = ⅕ af fokus", mode: "flow", run: function() { timer.startFocus("flow") } },
    { id: "b5", group: "Pause", icon: 0xF0176, label: "5 min", hint: "mikropause", run: function() { timer.takeBreak(5) } },
    { id: "b10", group: "Pause", icon: 0xF0176, label: "10 min", hint: "", run: function() { timer.takeBreak(10) } },
    { id: "b15", group: "Pause", icon: 0xF0176, label: "15 min", hint: "lang pause", run: function() { timer.takeBreak(15) } },
    { id: "lunch", group: "Pause", icon: 0xF0A70, label: "Frokost", hint: lunchMinutes + " min", run: function() { timer.takeBreak(lunchMinutes) } },
    { id: "skip", group: "-", icon: 0xF04AD, label: "Spring over", hint: "næste fase", needsActive: true, run: function() { timer.skip() } },
    { id: "stop", group: "-", icon: 0xF04DB, label: "Stop", hint: "nulstil", needsActive: true, run: function() { timer.stop() } }
  ]

  readonly property var info: ({
    toggle: "Starter, pauser eller fortsætter den aktuelle fase. Samme som venstreklik på timeren.",
    classic: "25 min fokus og 5 min pause. Efter 4 runder en lang pause på 15 min. Passer til de fleste opgaver.",
    deep: "50 min fokus og 10 min pause, 30 min pause efter 2 runder. Til krævende arbejde, hvor 25 min er for kort.",
    flow: "Tæller op. Arbejd, til fokus slipper, og tag så pausen (9 eller midterklik). Pausen bliver ⅕ af fokustiden, 2–30 min.",
    b5: "Kort pause nu: rejs dig, kig langt væk og drik vand. Telefonen genoplader dårligt.",
    b10: "Pause nu. En afbrudt fokusrunde tæller ikke med mod den lange pause.",
    b15: "Lang pause nu. Længere pauser hjælper mere efter krævende arbejde.",
    lunch: "Frokostpause. Længden ændres under Indstillinger.",
    skip: "Afslut den aktuelle fase: fra fokus til pause, eller fra pause til fokus.",
    stop: "Stop timeren og nulstil runderne.",
    settings: "Frokostlængde, pauseskærm og hvilke punkter der vises i menuen.",
    lunchLength: "Længden på frokostpausen. Brug ← → eller klik på pilene.",
    breakscreen: "Fuldskærm med nedtælling i pauserne: kun i Dyb, i alle pauser eller fra. L låser, hold Esc springer over.",
    visibility: "Vis eller skjul punktet i menuen. Synlige punkter nummereres 1–9, 0.",
    back: "Tilbage til menuen."
  })

  function keyFor(i) { return String((i + 1) % 10) }

  readonly property var rows: {
    var list = []
    var i
    if (settingsView) {
      list.push({ kind: "lunch", group: "Frokostpause", key: "", icon: 0xF0A70, label: "Længde",
        hint: "‹  " + lunchMinutes + " min  ›", info: info.lunchLength })
      var screenMode = timer ? timer.breakScreenMode : "deep"
      list.push({ kind: "breakscreen", group: "Pauseskærm", key: "", icon: screenMode === "off" ? 0xF0131 : 0xF0132,
        label: "Vis i pauser", hint: "‹  " + ({ deep: "kun dyb", all: "alle", off: "fra" })[screenMode] + "  ›",
        dim: screenMode === "off", info: info.breakscreen })
      for (i = 0; i < allActions.length; i++) {
        var a = allActions[i]
        var shown = hiddenItems.indexOf(a.id) < 0
        list.push({ kind: "visibility", id: a.id, group: "Vis i menuen", key: keyFor(i),
          icon: shown ? 0xF0132 : 0xF0131, label: a.menuLabel || a.label,
          hint: a.group === "-" ? "" : a.group.toLowerCase(), current: false, dim: !shown, info: info.visibility })
      }
      list.push({ kind: "back", group: "-", key: "esc", icon: 0xF004D, label: "Tilbage", hint: "", info: info.back })
      return list
    }
    var n = 0
    for (i = 0; i < allActions.length; i++) {
      var b = allActions[i]
      if (hiddenItems.indexOf(b.id) >= 0) continue
      list.push({ kind: "action", action: b, group: b.group, key: keyFor(n++), icon: b.icon, label: b.label,
        hint: b.hint, info: info[b.id] || "", current: !!b.mode && !!timer && timer.mode === b.mode,
        disabled: !timer || (b.needsActive && timer.stopped) })
    }
    list.push({ kind: "settings", group: "-settings", key: "s", icon: 0xF0493, label: "Indstillinger", hint: "", info: info.settings })
    return list
  }

  function enabledAt(i) {
    return i >= 0 && i < rows.length && !rows[i].disabled
  }

  function activate(i) {
    if (!enabledAt(i) || !timer) return
    var row = rows[i]
    if (row.kind === "action") { row.action.run(); close() }
    else if (row.kind === "settings") showSettings(true)
    else if (row.kind === "back") showSettings(false)
    else if (row.kind === "visibility") timer.toggleHidden(row.id)
    else if (row.kind === "breakscreen") timer.cycleBreakScreen(1)
    else if (row.kind === "lunch") timer.setLunchMinutes(lunchMinutes + 5)
  }

  // Lunch length and break-screen mode are steppers: ← / → move them.
  function step(row, delta) {
    if (!timer || !row) return
    if (row.kind === "lunch") adjustLunch(delta)
    else if (row.kind === "breakscreen") timer.cycleBreakScreen(delta)
  }

  function adjustLunch(delta) {
    if (timer) timer.setLunchMinutes(lunchMinutes + delta * 5)
  }

  function showSettings(value) {
    settingsView = value
    selected = 0
  }

  function move(delta) {
    var n = rows.length
    var i = selected
    do { i = ((i + delta) % n + n) % n } while (!enabledAt(i) && i !== selected)
    selected = i
  }

  function horizontal(dx) {
    var row = rows[selected]
    if (settingsView && row && (row.kind === "lunch" || row.kind === "breakscreen")) step(row, dx)
    else move(dx)
  }

  function keyPressed(t) {
    if (t === "s" || t === "S") { showSettings(!settingsView); return }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].key === t) { selected = i; activate(i); return }
    }
  }

  function open() {
    settingsView = false
    selected = 0
    controller.show()
  }

  function close() {
    controller.hide()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: content.implicitHeight + panel.verticalContentInset

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.move(dy)
        else root.horizontal(dx)
      }
      onActivateRequested: root.activate(root.selected)
      onCloseRequested: root.settingsView ? root.showSettings(false) : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.keyPressed(t) }

      Column {
        id: content
        width: parent.width
        spacing: 0

        // ---- Header: live status, or the settings title
        Item {
          width: parent.width
          height: header.implicitHeight + Style.space(12)

          Column {
            id: header
            width: parent.width
            spacing: Style.space(2)

            Text {
              text: root.settingsView ? "Pomodoro"
                : !root.timer ? "Pomodoro"
                : root.timer.stopped ? "Pomodoro · " + root.timer.modeLabel
                : root.timer.ready ? "Pausen er slut"
                : root.timer.phaseLabel + " · " + root.timer.modeLabel
              color: root.timer && root.timer.onBreak && !root.settingsView ? root.accent : root.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Row {
              spacing: Style.space(10)

              Text {
                id: bigTime
                text: root.settingsView ? "Indstillinger"
                  : !root.timer || root.timer.ready ? "--:--"
                  : (root.timer.countingUp ? "↑" : "") + root.timer.remainingText
                color: root.timer && root.timer.paused && !root.settingsView ? root.muted : root.foreground
                font.family: root.fontFamily
                font.pixelSize: root.settingsView ? Style.font.display : Style.font.displayLarge
                font.bold: true
              }

              Text {
                y: bigTime.baselineOffset - baselineOffset
                text: root.settingsView || !root.timer || root.timer.stopped ? ""
                  : (root.timer.paused ? "på pause · " : "") + "runde " + root.timer.round
                    + (root.timer.mode === "flow" ? "" : "/" + root.timer.modeConfig().rounds)
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }
        }

        // ---- Rows
        Repeater {
          model: root.rows.length

          Column {
            id: entry
            required property int index
            readonly property var row: root.rows[index] || ({})
            readonly property var prevGroup: index > 0 && root.rows[index - 1] ? root.rows[index - 1].group : null
            readonly property bool newGroup: index === 0 || row.group !== prevGroup
            readonly property string sectionTitle: row.group && row.group.charAt(0) !== "-" ? row.group : ""
            readonly property bool hot: root.selected === index && !row.disabled
            readonly property bool accented: hot || !!row.current
            width: content.width

            Item {
              visible: entry.newGroup && (entry.index > 0 || entry.sectionTitle !== "")
              width: parent.width
              height: entry.sectionTitle !== "" ? Style.space(26) : Style.space(9)

              PanelSeparator {
                anchors.top: parent.top
                anchors.topMargin: Style.space(4)
                foreground: root.foreground
              }

              Text {
                visible: entry.sectionTitle !== ""
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(3)
                text: entry.sectionTitle.toUpperCase()
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1
              }
            }

            Rectangle {
              width: parent.width
              height: Style.space(30)
              radius: Style.space(4)
              color: entry.hot ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16) : "transparent"
              opacity: entry.row.disabled ? 0.35 : (entry.row.dim ? 0.55 : 1)

              Text {
                id: keyLabel
                anchors.left: parent.left
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                text: entry.row.key || ""
                color: entry.hot ? root.accent : root.muted
                font.family: root.fontFamily
                font.pixelSize: entry.row.key && entry.row.key.length > 1 ? Style.font.caption : Style.font.body
                font.bold: true
              }

              Text {
                id: iconLabel
                anchors.left: keyLabel.right
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(22)
                horizontalAlignment: Text.AlignHCenter
                text: entry.row.icon ? root.glyph(entry.row.icon) : ""
                color: entry.accented ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Text {
                anchors.left: iconLabel.right
                anchors.leftMargin: Style.space(8)
                anchors.right: hintLabel.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: (entry.row.label || "") + (entry.row.current ? "  ✓" : "")
                elide: Text.ElideRight
                color: entry.accented ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: !!entry.row.current
              }

              Text {
                id: hintLabel
                anchors.right: parent.right
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: entry.row.hint || ""
                readonly property bool stepper: entry.row.kind === "lunch" || entry.row.kind === "breakscreen"
                color: stepper ? root.foreground : root.muted
                font.family: root.fontFamily
                font.pixelSize: stepper ? Style.font.title : Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: entry.row.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                onEntered: if (!entry.row.disabled) root.selected = entry.index
                onClicked: function(mouse) {
                  // Steppers: left of the value's middle (‹) steps down, right of it (›) up.
                  if (hintLabel.stepper)
                    root.step(entry.row, mouse.x < hintLabel.x + hintLabel.width / 2 ? -1 : 1)
                  else root.activate(entry.index)
                }
                onWheel: function(wheel) {
                  if (hintLabel.stepper) root.step(entry.row, wheel.angleDelta.y > 0 ? 1 : -1)
                }
              }
            }
          }
        }

        // ---- Explanation of the selected/hovered row. Fixed height so the
        //      panel doesn't jump as the text changes.
        Item {
          width: parent.width
          height: Style.space(62)

          PanelSeparator {
            anchors.top: parent.top
            anchors.topMargin: Style.space(4)
            foreground: root.foreground
          }

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: Style.space(12)
            anchors.leftMargin: Style.space(8)
            anchors.rightMargin: Style.space(8)
            text: root.rows[root.selected] ? root.rows[root.selected].info || "" : ""
            wrapMode: Text.WordWrap
            maximumLineCount: 3
            elide: Text.ElideRight
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            lineHeight: 1.15
          }
        }
      }
    }
  }
}
