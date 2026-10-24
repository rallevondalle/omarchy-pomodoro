import QtQuick
import Quickshell
import Quickshell.Io

// Single timer shared by every bar instance (one per monitor). State is
// deadline-based and persisted, so suspend, plugin hot-reload and shell
// restarts don't lose or skew the countdown.
//
// Design choices, from the research on breaks:
// - Systematic breaks (Pomodoro) give less fatigue and better concentration
//   than "I'll break when I feel like it" (Biwer et al. 2023), so focus
//   always rolls straight into a break.
// - Flowtime (self-chosen focus length, break proportional to it) did as
//   well on productivity with a slower rise in fatigue (2025 follow-up),
//   so it is offered as a mode: break = focus / 5.
// - Longer breaks restore more after demanding work (Albulescu et al. 2022),
//   hence the deep mode and the long breaks.
// - A break that ends while you're away shouldn't start the next focus
//   without you, so a finished break waits in "ready" for a click.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")) + "/omarchy"
  readonly property string statePath: stateDir + "/rallevondalle-pomodoro.json"

  // Classic mode comes from the bar entry settings; the others are fixed.
  property var config: ({ work: 25, shortBreak: 5, longBreak: 15, rounds: 4 })
  readonly property int flowNudgeMinutes: 90

  // mode: classic | deep | flow
  // status: stopped | running | paused | ready (break over, waiting for you)
  // phase: work | short | long | manual
  property string mode: "classic"
  property string status: "stopped"
  property string phase: "work"
  property int round: 1
  property double deadlineMs: 0
  property double remainingMs: 0
  property double durationMs: 0
  property double startedMs: 0      // flow: start of the current running stretch
  property double elapsedMs: 0      // flow: focus time banked before that stretch
  property bool flowNudged: false

  // Panel preferences, edited from the panel's settings view.
  property int lunchMinutes: 45
  property var hiddenItems: []
  property double nowMs: Date.now()
  property bool loaded: false
  property bool dirReady: false

  readonly property bool running: status === "running"
  readonly property bool paused: status === "paused"
  readonly property bool stopped: status === "stopped"
  readonly property bool ready: status === "ready"
  readonly property bool onBreak: !stopped && !ready && phase !== "work"
  readonly property bool countingUp: mode === "flow" && phase === "work" && (running || paused)

  readonly property double flowElapsedMs: elapsedMs + (running && countingUp ? nowMs - startedMs : 0)
  readonly property int displaySeconds: Math.max(0, countingUp
    ? Math.floor(flowElapsedMs / 1000)
    : Math.ceil((running ? deadlineMs - nowMs : (paused ? remainingMs : phaseMs("work"))) / 1000))
  readonly property string remainingText: {
    var s = displaySeconds
    var m = Math.floor(s / 60)
    return (m < 10 ? "0" : "") + m + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
  }
  readonly property string phaseLabel: ({
    work: "Fokus", short: "Pause", long: "Lang pause", manual: "Pause"
  })[phase] || "Fokus"
  readonly property string modeLabel: ({
    classic: "Klassisk " + config.work + "/" + config.shortBreak,
    deep: "Dyb 50/10",
    flow: "Flow"
  })[mode] || mode

  readonly property var shortTips: [
    "Rejs dig og gå lidt rundt — bevægelse giver mest energi tilbage.",
    "Kig ud ad vinduet, langt væk, og giv øjnene fri fra skærmen.",
    "Drik et glas vand.",
    "Lad telefonen ligge — scrolling genoplader dårligere end en rigtig pause.",
    "Stræk nakke, skuldre og ryg.",
    "Luk øjnene og tag et par langsomme, dybe vejrtrækninger."
  ]
  readonly property var longTips: [
    "Gå udenfor, hvis du kan — frisk luft og dagslys.",
    "Spis eller drik noget, væk fra skærmen.",
    "Tag en snak med nogen — socialt samvær genoplader godt.",
    "Gå en rigtig tur og tænk på noget helt andet end arbejdet."
  ]

  function configure(settings) {
    function num(key, fallback) {
      var v = settings ? Number(settings[key]) : NaN
      return isFinite(v) && v > 0 ? v : fallback
    }
    config = {
      work: num("workMinutes", 25),
      shortBreak: num("shortBreakMinutes", 5),
      longBreak: num("longBreakMinutes", 15),
      rounds: Math.round(num("roundsPerLongBreak", 4))
    }
  }

  function modeConfig() {
    if (mode === "deep") return { work: 50, shortBreak: 10, longBreak: 30, rounds: 2 }
    return config
  }

  function phaseMs(p) {
    var c = modeConfig()
    var min = p === "work" ? c.work : (p === "long" ? c.longBreak : c.shortBreak)
    return min * 60 * 1000
  }

  function flowBreakMs(focusMs) {
    var min = Math.min(30, Math.max(2, Math.round(focusMs / 60000 / 5)))
    return min * 60 * 1000
  }

  function minutes(ms) {
    return Math.round(ms / 60000)
  }

  function beginWork() {
    var now = Date.now()
    phase = "work"
    status = "running"
    if (mode === "flow") {
      startedMs = now
      elapsedMs = 0
      flowNudged = false
      deadlineMs = 0
      durationMs = 0
      notify("Fokus — runde " + round, "Flow: arbejd så længe det kører, og tag pause når du mister fokus.")
    } else {
      durationMs = phaseMs("work")
      deadlineMs = now + durationMs
      remainingMs = durationMs
      notify("Fokus — runde " + round, minutes(durationMs) + " minutter. Én opgave, notifikationer væk.")
    }
    nowMs = now
    save()
  }

  // Starts a break that began at `fromMs` (the work deadline, so time asleep
  // or away counts as break). If it already ran out, go straight to ready.
  function beginBreak(kind, ms, fromMs, title) {
    phase = kind
    status = "running"
    durationMs = ms
    deadlineMs = fromMs + ms
    nowMs = Date.now()
    if (deadlineMs <= nowMs) {
      breakOver()
      return
    }
    var tips = kind === "long" || ms >= 15 * 60000 ? longTips : shortTips
    notify(title + " · " + minutes(ms) + " min", tips[(round + new Date().getMinutes()) % tips.length])
    save()
  }

  function finishWork(atMs) {
    var completed = round
    round = round + 1
    if (mode === "flow") {
      beginBreak("short", flowBreakMs(flowElapsedMs), atMs,
        "Godt arbejde (" + minutes(flowElapsedMs) + " min)")
      return
    }
    var c = modeConfig()
    var kind = completed % c.rounds === 0 ? "long" : "short"
    beginBreak(kind, phaseMs(kind), atMs, kind === "long" ? "Lang pause" : "Pause")
  }

  function breakOver() {
    status = "ready"
    phase = "work"
    nowMs = Date.now()
    notify("Pausen er slut", "Klik på timeren i baren for at starte runde " + round + ".")
    save()
  }

  // ---- Actions (bar clicks, menu, IPC)

  function toggle() {
    var now = Date.now()
    if (stopped) { round = 1; beginWork(); return }
    if (ready) { beginWork(); return }
    if (running) {
      if (countingUp) elapsedMs += now - startedMs
      else remainingMs = Math.max(0, deadlineMs - now)
      status = "paused"
    } else {
      if (countingUp) startedMs = now
      else deadlineMs = now + remainingMs
      status = "running"
    }
    nowMs = now
    save()
  }

  function startFocus(newMode) {
    if (newMode && newMode !== mode) {
      mode = newMode
      round = 1
    } else if (stopped) {
      round = 1
    }
    beginWork()
  }

  // A break inserted mid-focus discards the unfinished focus; the round
  // number stays, so the cycle towards the long break isn't cheated.
  function takeBreak(min) {
    var ms = Math.max(1, Number(min) || 5) * 60000
    beginBreak("manual", ms, Date.now(), "Pause")
  }

  function skip() {
    if (stopped) return
    if (ready || onBreak) beginWork()
    else finishWork(Date.now())
  }

  function stop() {
    status = "stopped"
    phase = "work"
    round = 1
    save()
  }

  function setMode(newMode) {
    if (newMode !== "classic" && newMode !== "deep" && newMode !== "flow") return
    if (newMode === mode) return
    mode = newMode
    if (!stopped && phase === "work") startFocus(newMode)
    else save()
  }

  function setLunchMinutes(min) {
    lunchMinutes = Math.max(15, Math.min(120, Math.round(Number(min) || 45)))
    save()
  }

  function toggleHidden(id) {
    var next = hiddenItems.slice()
    var i = next.indexOf(id)
    if (i >= 0) next.splice(i, 1)
    else next.push(id)
    hiddenItems = next
    save()
  }

  function adjust(min) {
    if (stopped || ready || countingUp) return
    var delta = min * 60000
    var now = Date.now()
    if (running) {
      deadlineMs = Math.max(now + 1000, deadlineMs + delta)
      durationMs = Math.max(durationMs, deadlineMs - now)
    } else {
      remainingMs = Math.max(1000, remainingMs + delta)
      durationMs = Math.max(durationMs, remainingMs)
    }
    nowMs = now
    save()
  }

  function tick() {
    nowMs = Date.now()
    if (!running) return
    if (countingUp) {
      if (!flowNudged && flowElapsedMs >= flowNudgeMinutes * 60000) {
        flowNudged = true
        save()
        notify(flowNudgeMinutes + " minutters fokus", "Tid til en pause? Midterklik på timeren for at tage den.")
      }
    } else if (nowMs >= deadlineMs) {
      if (phase === "work") finishWork(deadlineMs)
      else breakOver()
    }
  }

  function notify(title, body) {
    Quickshell.execDetached(["omarchy-notification-send", "--app-name", "pomodoro",
      "-g", phase === "work" ? "󱎫" : "󰅶", "-u", "normal", title, body])
  }

  // ---- Persistence

  function save() {
    if (!loaded || !dirReady) return
    stateFile.setText(JSON.stringify({
      mode: mode, status: status, phase: phase, round: round,
      deadlineMs: deadlineMs, remainingMs: remainingMs, durationMs: durationMs,
      startedMs: startedMs, elapsedMs: elapsedMs, flowNudged: flowNudged,
      lunchMinutes: lunchMinutes, hiddenItems: hiddenItems
    }) + "\n")
  }

  function restore(text) {
    try {
      var s = JSON.parse(text)
      if (s) {
        if (s.mode === "classic" || s.mode === "deep" || s.mode === "flow") mode = s.mode
        if (Number(s.lunchMinutes) > 0) lunchMinutes = Number(s.lunchMinutes)
        if (Array.isArray(s.hiddenItems)) hiddenItems = s.hiddenItems
        if (["running", "paused", "ready"].indexOf(s.status) >= 0) {
          phase = s.phase || "work"
          round = s.round || 1
          deadlineMs = Number(s.deadlineMs) || 0
          remainingMs = Number(s.remainingMs) || 0
          durationMs = Number(s.durationMs) || 0
          startedMs = Number(s.startedMs) || 0
          elapsedMs = Number(s.elapsedMs) || 0
          flowNudged = !!s.flowNudged
          status = s.status
        }
      }
    } catch (e) {}
    loaded = true
    tick()
  }

  Component.onCompleted: mkdir.running = true

  Process {
    id: mkdir
    command: ["mkdir", "-p", root.stateDir]
    onExited: function(code) {
      root.dirReady = code === 0
      reader.running = true
    }
  }

  // FileView doesn't report a missing file reliably, so the initial read
  // goes through cat; FileView is only used for atomic writes.
  Process {
    id: reader
    command: ["cat", root.statePath]
    stdout: StdioCollector { id: readerOut }
    onExited: root.restore(readerOut.text)
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    blockLoading: false
    preload: false
  }

  Timer {
    interval: 250
    repeat: true
    running: root.loaded && root.running
    onTriggered: root.tick()
  }

  IpcHandler {
    target: "rallevondalle.pomodoro"

    function toggle(): void { root.toggle() }
    function stop(): void { root.stop() }
    function skip(): void { root.skip() }
    function focus(mode: string): void { root.startFocus(mode) }
    function takeBreak(minutes: int): void { root.takeBreak(minutes) }
    function lunch(): void { root.takeBreak(root.lunchMinutes) }
    function setMode(mode: string): void { root.setMode(mode) }
    function mode(): string { return root.mode }
    function status(): string {
      return root.mode + " " + root.status + " " + root.phase + " r" + root.round + " " + root.remainingText
    }
  }
}
