import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "t3mon.battery-guard"
  ipcTarget: "t3mon.battery-guard"
  manageIpc: false

  readonly property var cfg: Model.readSettings(root.settings)
  readonly property var device: UPower.displayDevice
  readonly property bool present: !!(root.device && root.device.isPresent)
  readonly property int pct: Model.level(root.device)
  readonly property bool batteryPowered: UPower.onBattery
  readonly property string reminderKind: Model.wantedReminder(root.pct, root.batteryPowered, root.cfg)
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color muted: Qt.darker(root.fg, 1.4)
  readonly property color warn: root.reminderKind === "plugIn" ? Commons.Color.urgent : Commons.Color.accent
  readonly property string glyph: root.cfg.travel ? "󰀝" : "󰕥"

  property int cursor: 0
  property bool cursorActive: false
  readonly property int rowCount: 3
  property var info: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property var palette: ({})
  readonly property bool showPercentage: root.setting("showPercentage", false) === true
  readonly property string flowState: Model.flow(root.info, root.batteryPowered)
  readonly property color charging: root.palette.green ? root.palette.green : "#a3be8c"
  readonly property color discharging: Qt.lighter(root.palette.yellow ? root.palette.yellow : "#ebcb8b", 1.12)
  readonly property color flowColor: root.flowState === "charging" ? root.charging : (root.flowState === "discharging" ? root.discharging : root.fg)
  readonly property real openPanelIndicatorWidth: root.showPercentage && !button.vertical ? button.glyphPaintedWidth : 0

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  PersistentProperties {
    id: memo
    reloadableId: "t3mon-battery-guard"
    property string kind: ""
    property real at: 0
    property int notifyId: 0
  }

  function tr(key, a, b) {
    var s = strings.t(key)
    if (a !== undefined && /%\d/.test(s)) s = s.arg(a)
    if (b !== undefined && /%\d/.test(s)) s = s.arg(b)
    return s
  }

  function num(v) {
    return Commons.I18n.formatNumber(v)
  }

  function save(key, value) {
    root.settings = Model.withSetting(root.settings, key, value)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
    memo.kind = ""
    memo.at = 0
    Qt.callLater(root.check)
  }

  function setTravel(on) {
    if (on === root.cfg.travel) return
    root.save("travel", on)
    if (on) root.notify("󰀝", root.tr("notify.travelOn"), root.tr("notify.travelOnBody"), "low", [])
    else root.notify("󰕥", root.tr("notify.dailyOn"), root.tr("notify.dailyOnBody", root.num(root.cfg.low), root.num(root.cfg.high)), "low", [])
  }

  function nudge(dir) {
    if (root.cursor === 0) root.setTravel(dir > 0)
    else if (root.cursor === 1 && root.profiles.length > 0)
      root.profileIndex = Math.max(0, Math.min(root.profiles.length - 1, root.profileIndex + dir))
  }

  function activate() {
    if (root.cursor === 0) root.setTravel(!root.cfg.travel)
    else if (root.cursor === 1) root.setProfile(root.profiles[root.profileIndex])
    else root.togglePercentage()
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function refresh() {
    if (!root.present) return
    if (!statsProc.running) statsProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function setProfile(name) {
    if (!name || actionProc.running) return
    actionProc.command = ["omarchy-powerprofiles-set", root.batteryPowered ? "battery" : "ac", name]
    actionProc.running = true
  }

  function reading(raw) {
    return String(raw === undefined || raw === null ? "" : raw).replace(/\d+(?:\.\d+)?/g, function(n) {
      var dot = n.indexOf(".")
      return Commons.I18n.formatNumber(Number(n), dot < 0 ? undefined : n.length - dot - 1)
    })
  }

  function profileLabel(name) {
    if (name === "power-saver") return root.tr("profile.powerSaver")
    if (name === "balanced") return root.tr("profile.balanced")
    if (name === "performance") return root.tr("profile.performance")
    return name.charAt(0).toUpperCase() + name.slice(1)
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.palette = Model.parsePalette(text())
  }

  Process {
    id: statsProc
    command: ["omarchy-battery-status", "--shell"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseKeyValue(text)
        if (Object.keys(next).length > 0) root.info = next
      }
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseProfiles(text)
        if (parsed.profiles.length === 0) return
        root.profiles = parsed.profiles
        root.activeProfile = parsed.active
        if (!root.cursorActive) root.profileIndex = Math.max(0, parsed.profiles.indexOf(parsed.active))
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  onBatteryPoweredChanged: if (root.opened) root.refresh()

  property var queued: null

  function notify(glyph, title, body, urgency, actions) {
    root.queued = { glyph: glyph, title: title, body: body, urgency: urgency, actions: actions }
    if (!notifyProc.running) root.flush()
  }

  function flush() {
    var n = root.queued
    if (!n) return
    root.queued = null
    var cmd = ["omarchy-notification-send", "--app-name", "Battery Guard", "-g", n.glyph, "-u", n.urgency, "-t", "20000", "-p"]
    if (memo.notifyId > 0) cmd.push("-r", String(memo.notifyId))
    cmd.push(n.title, n.body)
    for (var i = 0; i < n.actions.length; i++) cmd.push("--action", n.actions[i].label, "omarchy-shell", root.ipcTarget, n.actions[i].call)
    notifyProc.command = cmd
    notifyProc.running = true
  }

  function check() {
    if (!root.present) return
    var res = Model.step({ kind: memo.kind, at: memo.at }, root.reminderKind, Date.now(), root.cfg)
    memo.kind = res.memory.kind
    memo.at = res.memory.at
    if (!res.notify) return
    var p = root.num(root.pct)
    if (memo.kind === "plugIn")
      root.notify("󰂃", root.tr("notify.plugInTitle", p), root.tr("notify.plugInBody", root.num(root.cfg.low)), "critical", [])
    else if (memo.kind === "unplug")
      root.notify("󰂄", root.tr("notify.unplugTitle", p), root.tr("notify.unplugBody"), "normal", [{ label: root.tr("notify.travelAction"), call: "travelOn" }])
    else if (memo.kind === "full")
      root.notify("󰁹", root.tr("notify.fullTitle"), root.tr("notify.fullBody"), "normal", [{ label: root.tr("notify.dailyAction"), call: "travelOff" }])
  }

  onReminderKindChanged: root.check()

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.check()
  }

  Process {
    id: notifyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var n = parseInt(String(text).trim(), 10)
        if (!isNaN(n) && n > 0) memo.notifyId = n
      }
    }
    onExited: Qt.callLater(root.flush)
  }

  ShellIpc {
    target: "t3mon.battery-guard"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function travelOn(): void { root.setTravel(true) }
    function travelOff(): void { root.setTravel(false) }
    function toggleTravel(): void { root.setTravel(!root.cfg.travel) }
    function togglePercentage(): void { root.togglePercentage() }
    function status(): string {
      return JSON.stringify({ level: root.pct, onBattery: root.batteryPowered, travel: root.cfg.travel, low: root.cfg.low, high: root.cfg.high, repeatMinutes: root.cfg.repeatMinutes, reminder: root.reminderKind })
    }
  }

  onOpenedChanged: {
    if (!opened) return
    root.cursorActive = false
    root.cursor = 0
    root.refresh()
  }

  visible: root.present
  implicitWidth: root.present ? button.implicitWidth : 0
  implicitHeight: root.present ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    labelText: root.showPercentage && !vertical && root.pct >= 0 ? root.num(root.pct) + "%" : ""
    slotSize: Style.bar.iconSlot * (root.showPercentage && !vertical ? 2 : 1)
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) root.setTravel(!root.cfg.travel)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.present
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.cursor = Math.max(0, Math.min(root.rowCount - 1, root.cursor + dy))
        else if (dx !== 0) root.nudge(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activate()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroPercent.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyph
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.tr("title")
              color: root.fg
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.tr(Model.statusKey(root.pct, root.batteryPowered, root.cfg), root.num(root.cfg.high)).toUpperCase()
              color: root.reminderKind !== "" ? root.warn : root.muted
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }

          Text {
            id: heroPercent
            textFormat: Text.PlainText
            text: root.pct >= 0 ? root.num(root.pct) + "%" : "—"
            color: root.fg
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.displayLarge
            font.bold: true
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          width: parent.width
          implicitHeight: Style.space(10)

          Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
          }


          Rectangle {
            height: track.height
            radius: track.radius
            color: root.flowColor
            Behavior on color { ColorAnimation { duration: Style.duration(200) } }
            width: Math.max(track.height, track.width * Math.max(0, root.pct) / 100)
            Behavior on width { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
          }

          Repeater {
            model: root.cfg.travel ? [] : [root.cfg.low, root.cfg.high]
            Rectangle {
              required property var modelData
              x: track.width * modelData / 100 - width / 2
              y: -Style.space(3)
              width: Style.space(3)
              height: track.height + Style.space(6)
              radius: width / 2
              color: Commons.Color.accent
            }
          }
        }

        Row {
          visible: root.info.percentage !== undefined
          width: parent.width
          spacing: Style.space(20)

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair { label: root.tr("stat.size"); value: root.reading(root.info.size) || "—" }
            InfoPair { label: root.tr("stat.cycles"); value: root.reading(root.info.cycles) || "—" }
          }

          Column {
            width: (parent.width - parent.spacing) / 2
            spacing: Style.spacing.labelGap
            InfoPair {
              label: root.flowState === "charging" ? root.tr("stat.toFull") : (root.flowState === "discharging" ? root.tr("stat.timeLeft") : root.tr("stat.time"))
              value: root.flowState === "idle" ? "—" : (root.info.time || "—")
              valueColor: root.flowColor
            }
            InfoPair {
              label: root.flowState === "charging" ? root.tr("stat.charging") : (root.flowState === "discharging" ? root.tr("stat.discharging") : root.tr("stat.holding"))
              value: root.flowState === "idle" ? "—" : (root.reading(root.info.rate) || "—")
              valueColor: root.flowColor
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: root.tr("section.mode").toUpperCase()
            foreground: root.fg
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: modeRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: (width - spacing) / 2

            Button {
              width: modeRow.cell
              iconText: "󰕥"
              iconSize: Style.font.title
              text: root.tr("mode.daily") + "  " + root.tr("mode.dailyRange", root.num(root.cfg.low), root.num(root.cfg.high))
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: !root.cfg.travel
              hasCursor: root.cursorActive && root.cursor === 0 && !root.cfg.travel
              onClicked: root.setTravel(false)
            }

            Button {
              width: modeRow.cell
              iconText: "󰀝"
              iconSize: Style.font.title
              text: root.tr("mode.travel") + "  " + root.tr("mode.travelRange")
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.bar.fontFamily
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.cfg.travel
              hasCursor: root.cursorActive && root.cursor === 0 && root.cfg.travel
              onClicked: root.setTravel(true)
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: root.tr("section.profile").toUpperCase()
            foreground: root.fg
            fontFamily: root.bar.fontFamily
          }

          Row {
            id: profileRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cell: root.profiles.length > 0 ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length : 0

            Repeater {
              model: root.profiles
              Button {
                required property var modelData
                required property int index
                width: profileRow.cell
                iconText: Model.profileIcon(String(modelData))
                iconSize: Style.font.title
                text: root.profileLabel(String(modelData))
                fontSize: Style.font.bodySmall
                foreground: root.fg
                fontFamily: root.bar.fontFamily
                verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
                bordered: true
                active: root.activeProfile === modelData
                hasCursor: root.cursorActive && root.cursor === 1 && root.profileIndex === index
                onClicked: root.setProfile(String(modelData))
              }
            }
          }
        }

        PanelSeparator { foreground: root.fg }

        Toggle {
          width: parent.width
          label: root.tr("option.percentage")
          checked: root.showPercentage
          hasCursor: root.cursorActive && root.cursor === 2
          foreground: root.fg
          fontFamily: root.bar.fontFamily
          titleSize: Style.font.bodySmall
          onClicked: root.togglePercentage()
        }
      }
    }
  }

  component InfoPair: Item {
    property string label: ""
    property string value: ""
    property color valueColor: root.fg

    width: parent.width
    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

    Text {
      id: pairLabel
      anchors.left: parent.left
      textFormat: Text.PlainText
      text: parent.label
      color: root.fg
      opacity: 0.6
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: pairValue
      anchors.right: parent.right
      textFormat: Text.PlainText
      text: parent.value
      color: parent.valueColor
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.bodySmall
      Behavior on color { ColorAnimation { duration: Style.duration(200) } }
    }
  }
}
