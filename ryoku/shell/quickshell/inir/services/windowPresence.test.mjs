import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { countOnActiveWorkspace } = require("./windowPresence.js");

let failed = 0;
function eq(actual, expected, message) {
    if (actual === expected) console.log("PASS " + message);
    else { failed++; console.log("FAIL " + message + "\n  expected " + expected + "\n  got      " + actual); }
}

const workspaces = [
    { id: "1", output: "eDP-1", is_active: true },
    { id: "2", output: "eDP-1", is_active: false },
    { id: "3", output: "DP-1", is_active: true }
];
const toplevel = minimized => ({ minimized });

const live = [
    { workspace: "1", toplevel: toplevel(false) },
    { workspace: "1", toplevel: toplevel(true) },
    { workspace: "2", toplevel: toplevel(false) },
    { workspace: "3", toplevel: toplevel(false) }
];
eq(countOnActiveWorkspace(live, workspaces, "eDP-1"), 1,
    "only unminimized toplevels on the output's active workspace count");
eq(countOnActiveWorkspace(live, workspaces, "DP-1"), 1,
    "each output uses its own active workspace");
eq(countOnActiveWorkspace(live, workspaces, "HDMI-A-1"), 0,
    "an output with no active workspace has no deck frost");

const leakedLayers = [
    { workspace: "1", appId: "ryoku-widgets", title: "layer-shell", toplevel: null },
    { workspace: "1", appId: "ryoku-frame", title: "layer-shell" },
    { workspace: "1", appId: "qs-dock", title: "layer-shell", toplevel: null },
    { workspace: "1", appId: "kitty", title: "terminal", toplevel: toplevel(false) }
];
eq(countOnActiveWorkspace(leakedLayers, workspaces, "eDP-1"), 1,
    "layer-shell residue cannot deepen the haze over the wallpaper");
eq(countOnActiveWorkspace(leakedLayers.slice(0, 3), workspaces, "eDP-1"), 0,
    "a desktop containing only shell surfaces stays clear");
eq(countOnActiveWorkspace(undefined, workspaces, "eDP-1"), 0,
    "missing window state fails open");
eq(countOnActiveWorkspace(live, undefined, "eDP-1"), 0,
    "missing workspace state fails open");

if (failed > 0) { console.log("\n" + failed + " test(s) FAILED"); process.exit(1); }
console.log("\nAll tests PASSED");
