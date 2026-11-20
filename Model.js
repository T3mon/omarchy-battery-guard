var DEFAULTS = { low: 20, high: 80, travel: false, repeatMinutes: 5 }

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

function toInt(v, fallback) {
  var n = parseInt(v, 10)
  return isNaN(n) ? fallback : n
}

function readSettings(settings) {
  var s = settings || {}
  var low = clamp(toInt(s.low, DEFAULTS.low), 5, 50)
  var high = clamp(toInt(s.high, DEFAULTS.high), 50, 100)
  if (high - low < 10) high = Math.min(100, low + 10)
  return {
    low: low,
    high: high,
    travel: s.travel === true,
    repeatMinutes: clamp(toInt(s.repeatMinutes, DEFAULTS.repeatMinutes), 0, 120)
  }
}

function withSetting(settings, key, value) {
  var cur = readSettings(settings)
  if (key === "low") cur.low = clamp(toInt(value, cur.low), 5, Math.min(50, cur.high - 10))
  else if (key === "high") cur.high = clamp(toInt(value, cur.high), Math.max(50, cur.low + 10), 100)
  else if (key === "travel") cur.travel = value === true
  else if (key === "repeatMinutes") cur.repeatMinutes = clamp(toInt(value, cur.repeatMinutes), 0, 120)
  return Object.assign({}, settings || {}, cur)
}

function level(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function wantedReminder(pct, onBattery, cfg) {
  if (pct < 0) return ""
  if (onBattery) return pct <= cfg.low ? "plugIn" : ""
  if (cfg.travel) return pct >= 100 ? "full" : ""
  return pct >= cfg.high ? "unplug" : ""
}

function step(memory, kind, now, cfg) {
  var last = memory || { kind: "", at: 0 }
  if (kind === "") return { notify: false, memory: { kind: "", at: 0 } }
  if (last.kind !== kind) return { notify: true, memory: { kind: kind, at: now } }
  if (kind === "full" || cfg.repeatMinutes <= 0) return { notify: false, memory: last }
  if (now - last.at >= cfg.repeatMinutes * 60000) return { notify: true, memory: { kind: kind, at: now } }
  return { notify: false, memory: last }
}

function statusKey(pct, onBattery, cfg) {
  var kind = wantedReminder(pct, onBattery, cfg)
  if (kind !== "") return "status." + kind
  if (onBattery) return "status.onBattery"
  return cfg.travel ? "status.chargingTravel" : "status.charging"
}

function parseKeyValue(raw) {
  var out = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length && i < 64; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    out[lines[i].substring(0, idx).trim()] = lines[i].substring(idx + 1).trim().slice(0, 64)
  }
  return out
}

function parseProfiles(raw) {
  var list = []
  var active = ""
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length && list.length < 8; i++) {
    var parts = lines[i].trim().split("\t")
    if (!/^[a-z-]{1,32}$/.test(parts[0])) continue
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return { profiles: list, active: active }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function parsePalette(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/)
    if (m) out[m[1]] = m[2]
  }
  return out
}

function flow(info, onBattery) {
  var st = String((info || {}).state || "")
  if (st === "charging") return "charging"
  if (st === "discharging") return "discharging"
  if (st === "") return onBattery ? "discharging" : "charging"
  return "idle"
}

if (typeof module !== "undefined") {
  module.exports = { DEFAULTS: DEFAULTS, readSettings: readSettings, withSetting: withSetting, level: level, wantedReminder: wantedReminder, step: step, statusKey: statusKey, parseKeyValue: parseKeyValue, parseProfiles: parseProfiles, profileIcon: profileIcon, parsePalette: parsePalette, flow: flow }
}
