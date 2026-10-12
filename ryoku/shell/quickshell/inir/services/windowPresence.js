// Count only protocol-joined application toplevels. Provider residue can be
// broader during startup or after a plugin reload, and a cosmetic desktop haze
// must fail open rather than cover the wallpaper because layer surfaces leaked
// into that residue.
function countOnActiveWorkspace(windows, workspaces, outputName) {
    var active = [];
    var output = String(outputName || "");
    var wsCount = workspaces ? workspaces.length : 0;
    for (var i = 0; i < wsCount; i++) {
        var workspace = workspaces[i];
        if (!workspace || workspace.is_active !== true)
            continue;
        if (output !== "" && workspace.output !== output)
            continue;
        active.push(workspace.id);
    }
    if (active.length === 0)
        return 0;

    var count = 0;
    var windowCount = windows ? windows.length : 0;
    for (var j = 0; j < windowCount; j++) {
        var window = windows[j];
        if (!window || !window.toplevel || window.toplevel.minimized === true)
            continue;
        if (active.indexOf(window.workspace) !== -1)
            count++;
    }
    return count;
}

if (typeof module !== "undefined" && module.exports)
    module.exports = { countOnActiveWorkspace };
