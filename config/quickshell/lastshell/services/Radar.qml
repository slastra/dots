pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import ".."  // root module: Deskwatch

// Storms near home, from the "storms" section deskwatch's news.storms
// collector publishes into the snapshot Deskwatch reads. The daemon
// owns every judgement (tiers, tracks, ETAs); this only reads, ages and
// summarises. Colouring lives in RadarChip: Theme is not in scope here.
Singleton {
    id: root

    property bool loaded: false
    property var payload: ({})
    property var storms: []
    property var homeAlerts: []
    property var warnings: []
    property var images: ({})
    property string updated: ""
    property int age: 0                 // seconds since the daemon wrote it

    // A payload the daemon has stopped refreshing is not a forecast.
    readonly property bool fresh: loaded && updated !== "" && age < 600
    readonly property bool active: fresh && payload.active === true

    function hasEvent(name) { return homeAlerts.some(a => a.event === name) }
    readonly property bool tornadoWarning: hasEvent("Tornado Warning")
    readonly property bool severeWarning: hasEvent("Severe Thunderstorm Warning")
    readonly property bool watch: hasEvent("Tornado Watch") || hasEvent("Severe Thunderstorm Watch")
    readonly property var threats: storms.filter(s => s.tier === "urgent" || s.tier === "high")
    readonly property bool urgent: tornadoWarning || storms.some(s => s.tier === "urgent")

    // quiet | near (storms around, none aimed at home) | watch | urgent
    readonly property string level: !active ? "quiet"
        : urgent ? "urgent"
        : (severeWarning || watch || threats.length > 0) ? "watch"
        : "near"

    // The storm the chip's badge counts down to: the daemon sorts threats
    // first, nearest closest-approach next.
    readonly property var nearest: threats.length > 0 ? threats[0] : null

    // Storms worth a row: any tier, or a real tornado or wind signal. A 0%
    // cell whose track crosses home is rain, not news.
    readonly property var notable: storms.filter(s =>
        s.tier !== "" || s.probtor >= 3 || s.probwind >= 20)

    function url(path) { return path ? "file://" + path : "" }

    function parseLocal(iso) { return iso ? new Date(iso) : null }

    // Wording shared by the chip, the ribbon and the view, so every surface
    // says a track the same way the phone notification does.
    function point(deg) {
        const p = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        return p[Math.floor(((deg + 11.25) % 360) / 22.5) % 16]
    }
    function miles(km) { const m = km / 1.609; return m < 1 ? "<1 mi" : `${Math.round(m)} mi` }
    function clock(iso) { const d = parseLocal(iso); return d ? Qt.formatTime(d, "h:mm AP") : "" }
    function probs(s) { return `tor ${s.probtor}% · wind ${s.probwind}% · hail ${s.probhail}%` }
    function where(s) {
        if (s.over_home) return "over home now"
        const now = `${miles(s.dist_km)} ${point(s.bearing)}, ${Math.round(s.mph)} mph → ${point(s.heading)}`
        return s.eta_min >= 0
            ? `${now} · passes ${miles(s.cpa_km)} ${point(s.pass_dir)} ~${clock(s.eta_at)}`
            : `${now} · moving away`
    }
    function tierLabel(t) { return t === "urgent" ? "URGENT" : t === "high" ? "HIGH" : "" }

    function tick() {
        const t = parseLocal(updated)
        age = t ? Math.max(0, Math.round((Date.now() - t.getTime()) / 1000)) : 0
    }

    Timer { interval: 30000; running: root.loaded; repeat: true; onTriggered: root.tick() }

    // Deskwatch reads the snapshot (LASTSHELL_DESKWATCH_SNAPSHOT points the
    // harness at a fixture) and hands this its section as text, which only
    // changes when the storms collector has run.
    function parse() {
        if (!Deskwatch.loaded) return
        try {
            const s = Deskwatch.stormsJson !== "" ? JSON.parse(Deskwatch.stormsJson) : null
            root.payload = s ?? {}
            root.storms = s?.storms ?? []
            root.homeAlerts = s?.home_alerts ?? []
            root.warnings = s?.warnings ?? []
            root.images = s?.images ?? {}
            root.updated = s?.updated ?? ""
            root.loaded = true
            root.tick()
        } catch (e) {}
    }
    Connections {
        target: Deskwatch
        function onStormsJsonChanged() { root.parse() }
        function onLoadedChanged() { root.parse() }
    }
    Component.onCompleted: parse()
}
