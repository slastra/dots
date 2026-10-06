pragma Singleton
import Quickshell
import QtQuick

// What the shell knows about browsers, in one place: which window classes
// are browsers (the launcher hides them, SUPER+W reaches their tabs), how
// a notification's sender maps to a tabctl mediator, and how a window
// title reads as a page title. The table used to live in three files
// and had already drifted between them.
Singleton {
    // Anchored on purpose: a loose /chrom|zen/ would also swallow Chrome
    // PWAs (chrome-<id>-Profile_N, app windows the switcher can't reach)
    // and Zenity/zenmap.
    readonly property var classRe:
        /^(firefox(-\w+)?|librewolf|zen(-\w+)?|helium|brave-browser|vivaldi(-stable)?|chromium|google-chrome(-\w+)?|chrome)$/i
    function isBrowserClass(cls) { return classRe.test(cls ?? "") }

    // tabctl mediator ids, matched as substrings of desktop-entry / app name
    readonly property var mediators: ["firefox", "chromium", "chrome", "brave", "zen", "helium"]
    function mediatorFor(desktopEntry, appName) {
        const id = [desktopEntry, appName].filter(s => s).join(" ").toLowerCase()
        return mediators.find(b => id.includes(b)) ?? ""
    }
    // Hyprland classes: google-chrome / chromium / brave-browser / zen / …
    function classFrag(mediator) { return mediator === "chrome" ? "chrom" : mediator }

    // Window title minus the browser's own suffix = the active tab's title
    // (same table as tabstrip's snapshot.go).
    readonly property var titleSuffixes: [
        " — Mozilla Firefox", " — Mozilla Firefox Private Browsing",
        " - Google Chrome", " - Chromium", " - Brave", " — Zen Browser", " - Helium"]
    function pageTitle(t) {
        for (const suf of titleSuffixes)
            if (t.endsWith(suf)) return t.slice(0, -suf.length)
        return t
    }

    // "+ New … window" rows in the tab switcher
    readonly property var newWindow: [
        { name: "Firefox", cmd: ["firefox", "--new-window"] },
        { name: "Chrome",  cmd: ["google-chrome-stable", "--new-window"] },
    ]
}
