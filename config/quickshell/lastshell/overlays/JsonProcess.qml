import Quickshell.Io

// A one-shot command whose stdout is JSON: `result` carries the parsed
// value, or `fallback` when the output would not parse (empty output, a
// tool that is not installed). Start it with `running = true`.
Process {
    property var fallback: []
    signal result(var json)
    stdout: StdioCollector {
        onStreamFinished: {
            let v
            try { v = JSON.parse(text) } catch (e) { v = fallback }
            result(v)
        }
    }
}
