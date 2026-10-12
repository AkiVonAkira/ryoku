package main

import (
	"os"
	"strings"
	"testing"
)

// The shipped baseline is the first compose layer and the one file the
// package owns outright. Three mistakes hurt here: a section whose plugin is
// not in core.plugins (a bind that silently never fires, which is how the
// development rig shipped for weeks), a plugin missing that the store's rows
// or the act verbs dial (caps that lie), and leftovers from that rig riding
// along into users' sessions. This reads the repo's payload, the exact bytes
// the package installs, and pins all three.
func TestShippedBaselineIsHonest(t *testing.T) {
	raw, err := os.ReadFile("../../wayfire/wayfire.ini")
	if err != nil {
		t.Fatalf("read the shipped baseline: %v", err)
	}
	doc := parseIni(raw)
	if len(doc.sections) == 0 {
		t.Fatal("the shipped baseline parses to nothing")
	}

	loaded := map[string]bool{}
	plugins, _ := doc.get("core", "plugins")
	for _, p := range strings.Fields(plugins) {
		loaded[p] = true
	}
	if len(loaded) == 0 {
		t.Fatal("core.plugins lists no plugins")
	}

	for _, sec := range doc.sections {
		if sec.name == "core" || strings.HasPrefix(sec.name, "output:") {
			continue
		}
		if !loaded[sec.name] {
			t.Errorf("section [%s] has no plugin in core.plugins", sec.name)
		}
	}

	// What the rest of the desktop dials: the store's sections and gestures,
	// the caps, and the act verbs each need their plugin already loaded.
	for _, want := range []string{
		"animate", "autostart", "command", "decoration", "depthdeck",
		"fast-switcher", "gtk-shell", "idle", "ipc", "ipc-rules", "session-lock",
		"shortcuts-inhibit", "simple-tile", "vswipe", "window-rules", "wm-actions",
		"wsets", "xdg-activation",
	} {
		if !loaded[want] {
			t.Errorf("core.plugins is missing %q", want)
		}
	}

	pluginOrder := strings.Fields(plugins)
	if len(pluginOrder) == 0 || pluginOrder[len(pluginOrder)-1] != "autostart" {
		t.Errorf("core.plugins = %q; autostart must initialize after every capability provider", plugins)
	}

	if vwidth, _ := doc.get("core", "vwidth"); vwidth != "5" {
		t.Errorf("core.vwidth = %q, want 5 for the ten-workspace catalogue", vwidth)
	}
	if vheight, _ := doc.get("core", "vheight"); vheight != "2" {
		t.Errorf("core.vheight = %q, want 2 for the ten-workspace catalogue", vheight)
	}
	if xwayland, _ := doc.get("core", "xwayland"); xwayland != "true" {
		t.Errorf("core.xwayland = %q, want true for the variant's X11 apps", xwayland)
	}
	if saver, _ := doc.get("idle", "screensaver_timeout"); saver != "0" {
		t.Errorf("idle.screensaver_timeout = %q; ryoku-idle owns the timeout", saver)
	}
	if dpms, _ := doc.get("idle", "dpms_timeout"); dpms != "-1" {
		t.Errorf("idle.dpms_timeout = %q; ryoku-idle owns output power", dpms)
	}
	if tiled, _ := doc.get("simple-tile", "tile_by_default"); tiled != "all" {
		t.Errorf("simple-tile.tile_by_default = %q, want all", tiled)
	}
	for _, key := range []string{
		"key_toggle", "key_focus_above", "key_focus_below", "key_focus_left",
		"key_focus_right", "key_toggle_maximized",
	} {
		if got, _ := doc.get("simple-tile", key); got != "none" {
			t.Errorf("simple-tile.%s = %q; the shared catalogue owns keyboard actions", key, got)
		}
	}

	// The rig's leftovers stay out: each of these sections shipped while its
	// plugin was off, so their binds did nothing, and the depth deck's knobs
	// belong to the store rather than to two copies of the same defaults.
	for _, dead := range []string{
		"alpha", "cube", "depthdeck", "expo", "fisheye",
		"invert", "oswitch", "switcher", "wayfire-shell", "wrot",
	} {
		for _, sec := range doc.sections {
			if sec.name == dead {
				t.Errorf("section [%s] belongs to a plugin this baseline does not run", dead)
			}
		}
	}

	// The catalogue owns its binds now: apply writes them beside this layer,
	// so a command row here would be a second copy waiting to drift.
	if term, _ := doc.get("command", "command_app_terminal"); term != "" {
		t.Errorf("command_app_terminal = %q; the baseline must not carry a second copy of the catalogue", term)
	}
	if cmd := defaultBinds()["app.terminal"].cmd; cmd != "ryoku-app terminal" {
		t.Errorf("app.terminal = %q, want the ryoku app verb", cmd)
	}

	// The login bootstrap: nothing else brings the session up, so a wayfire
	// login without this row is a bare compositor with no shell, no portals
	// restart and no depthdeck, and every other row here would be config for
	// a desktop that never starts.
	session, _ := doc.get("autostart", "0_session")
	for _, want := range []string{
		"dbus-update-activation-environment --systemd --all",
		"ryoku-power-cutover session-start-logged",
		"xdg-desktop-portal-wlr.service",
	} {
		if !strings.Contains(session, want) {
			t.Errorf("autostart.0_session is missing %q", want)
		}
	}
	if wf, _ := doc.get("autostart", "autostart_wf_shell"); wf != "false" {
		t.Errorf("autostart_wf_shell = %q; the session's shell is Quickshell, not wf-panel", wf)
	}
}
