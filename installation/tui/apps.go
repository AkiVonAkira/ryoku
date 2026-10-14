// apps.go adapts the shared installer choices to picker rows and owns the
// optional app table. Required app rows name a desktop feature (a ryoku-app
// role or the stash menu) that breaks without the package. The same
// feature-to-package contract is gated by tests/shell-tool-availability.sh.
// Tools that are hard dependencies of ryoku-desktop never appear here:
// removing them would break a surface the user never touched, so the desktop
// owns them rather than the installer's picker.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-i18n"
	installerplan "ryoku-installerplan"
)

// flowIndex finds the wizard index of a step by key; the flow shifts when
// steps are added, so nothing may index it by literal position.
func flowIndex(flow []step, key string) int {
	for i, s := range flow {
		if s.key == key {
			return i
		}
	}
	return -1
}

func installerChoicesForVariant(variant string) installerplan.EditionPlan {
	if !isVoidVariant(variant) {
		return installerplan.ResolveSource(variant)
	}
	var paths []string
	if root := os.Getenv("RYOKU_REPO"); root != "" {
		paths = append(paths, filepath.Join(root, "void/packages/translations.tsv"))
	}
	paths = append(paths,
		"/usr/share/ryoku/void/packages/translations.tsv",
		filepath.Join("..", "..", "void", "packages", "translations.tsv"),
	)
	for _, path := range paths {
		data, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		plan, err := installerplan.ResolveEdition(data)
		if err != nil {
			panic(err)
		}
		return plan
	}
	panic(fmt.Sprintf("Void package table not found in %s", strings.Join(paths, ", ")))
}

func choiceItems(kind string, plan installerplan.EditionPlan, availableOnly bool) []item {
	var items []item
	for _, availability := range plan.Choices(kind) {
		if availableOnly && !availability.Available {
			continue
		}
		choice := availability.Choice
		hint := i18n.T(choice.TUIHint)
		if !availability.Available {
			hint = i18n.Tf("Unavailable on %s · %s", plan.Edition, availability.Reason)
		}
		items = append(items, item{choice.ID, i18n.T(choice.Label), hint})
	}
	return items
}

func browsers() []item {
	return choiceItems(installerplan.Browser, installerplan.ResolveSource("Arch"), true)
}

// cachyosBrowserHints replaces the shared hint of a browser the CachyOS
// repositories serve, which that edition installs from the repo, not the AUR.
var cachyosBrowserHints = map[string]string{"zen": "vertical tabs · CachyOS repo"}

func browsersForVariant(variant string) []item {
	items := choiceItems(installerplan.Browser, installerChoicesForVariant(variant), true)
	if variant == variantCachyOS {
		for i := range items {
			if hint, ok := cachyosBrowserHints[items[i].key]; ok {
				items[i].hint = i18n.T(hint)
			}
		}
	}
	return items
}

// shippedBrowserCount is how many browsers the edition can install: the None
// row is a choice, not a browser, so it stays out of the step's description.
func shippedBrowserCount(variant string) int {
	n := 0
	for _, availability := range installerChoicesForVariant(variant).Choices(installerplan.Browser) {
		if availability.Available && !availability.Choice.NoPackages {
			n++
		}
	}
	return n
}

// browserLabel is the display name for a browser key, for Review and the rail.
func browserLabel(key string) string {
	for _, b := range browsers() {
		if b.key == key {
			return b.label
		}
	}
	return key
}

// loginShells returns the account shells in shared manifest order.
func loginShells() []item {
	return choiceItems(installerplan.LoginShell, installerplan.ResolveSource("Arch"), true)
}

func loginShellsForVariant(variant string) []item {
	return choiceItems(installerplan.LoginShell, installerChoicesForVariant(variant), true)
}

// loginShellLabel is the display name for a shell key, for Review and the rail.
func loginShellLabel(key string) string {
	for _, s := range loginShells() {
		if s.key == key {
			return s.label
		}
	}
	return key
}

// appRow is one keep/remove decision: a named app or tool group, the packages
// it stands for, and its honesty labels. Req is why the row cannot be removed
// (empty = removable); Sub is what it does; Group heads a section of rows.
type appRow struct {
	ID    string
	Name  string
	Pkgs  []string
	Def   bool
	Req   string
	Sub   string
	Group string
}

// appRows is the shipped-app table. Order is display order; membership mirrors
// ryokumanifest.Apps() (deliver-once apps), the AUR extras, and the feature-to-
// package map in tests/shell-tool-availability.sh (role apps are required).
func appRows() []appRow {
	return []appRow{
		{ID: "terminal", Name: "Kitty", Pkgs: []string{"kitty"}, Def: true, Group: i18n.T("System (required)"),
			Req: i18n.T("the Ryoku terminal role: the launcher's terminal, the Hub, and 'open in terminal' all run it")},
		{ID: "files", Name: "Files", Pkgs: []string{"nautilus"}, Def: true,
			Req: i18n.T("the Ryoku file-manager role: the launcher's Files, the stash, and the wallpaper picker open it")},
		{ID: "stash-menu", Name: "Files stash menu", Pkgs: []string{"nautilus-python"}, Def: true,
			Req: i18n.T("the Ryoku stash actions in the Files right-click menu (ships with Files)")},
		{ID: "editor", Name: "Neovim", Pkgs: []string{"neovim"}, Def: true,
			Req: i18n.T("the Ryoku editor role: the launcher's editor opens 'kitty -e nvim'")},

		{ID: "prompt", Name: "Starship prompt", Pkgs: []string{"starship"}, Def: true, Group: i18n.T("Terminal"),
			Sub: i18n.T("the Ryoku shell prompt")},
		{ID: "fastfetch", Name: "Fastfetch", Pkgs: []string{"fastfetch"}, Def: true,
			Sub: i18n.T("system summary card (launcher, RyoStore covers)")},
		{ID: "yazi", Name: "Yazi", Pkgs: []string{"yazi"}, Def: true,
			Sub: i18n.T("terminal file manager")},
		{ID: "monitor", Name: "btop monitor", Pkgs: []string{"btop"}, Def: true,
			Req: i18n.T("the CPU, GPU, and battery panels' monitor button opens btop in the terminal")},
		{ID: "cli-tools", Name: "Modern CLI tools", Pkgs: []string{"eza", "bat", "fzf", "zoxide"}, Def: true,
			Sub: i18n.T("ls/cat replacements · Ctrl-R + fuzzy cd in the shell (each degrades cleanly if removed)")},
		{ID: "git-tools", Name: "Git tools", Pkgs: []string{"github-cli", "lazygit"}, Def: true,
			Sub: i18n.T("the gh CLI and the lazygit terminal UI")},

		{ID: "pavucontrol", Name: "PulseAudio GUI", Pkgs: []string{"pavucontrol"}, Def: true, Group: i18n.T("Media & tools"),
			Sub: i18n.T("the mixer the bar's audio button opens")},
		{ID: "songrec", Name: "Songrec", Pkgs: []string{"songrec"}, Def: true,
			Sub: i18n.T("feature: Recognize Music in the launcher")},
		{ID: "openrgb", Name: "OpenRGB", Pkgs: []string{"openrgb"}, Def: true,
			Sub: i18n.T("feature: keyboard/mouse lighting follows the wallpaper palette")},
		{ID: "upscale", Name: "AI upscale", Pkgs: []string{"waifu2x-ncnn-vulkan"}, Def: true,
			Sub: i18n.T("feature: ryoshot Beautify HD and ryowalls Enhance")},
		{ID: "rashin", Name: "Rashin", Pkgs: []string{"ryoku-rashin"}, Def: true,
			Sub: i18n.T("feature: the AI agent (Ask, the Rashin window, the bar's AI usage pill)")},
		{ID: "localsend", Name: "LocalSend", Pkgs: []string{"localsend-bin"}, Def: true,
			Sub: i18n.T("feature: LAN file sharing (the pill's file stash speaks it; AUR)")},
		{ID: "voxtype", Name: "Voxtype", Pkgs: []string{"voxtype-bin"}, Def: true,
			Sub: i18n.T("feature: voice dictation on Super+` (AUR)")},

		{ID: "gamescope", Name: "Gamescope", Pkgs: []string{"gamescope"}, Def: true, Group: i18n.T("Gaming"),
			Sub: i18n.T("the nested gaming micro-compositor")},
		{ID: "gamemode", Name: "GameMode", Pkgs: []string{"gamemode"}, Def: true,
			Sub: i18n.T("the performance governor Steam invokes")},
		{ID: "mangohud", Name: "MangoHud", Pkgs: []string{"mangohud"}, Def: true,
			Sub: i18n.T("in-game FPS and frametime overlay")},
		{ID: "controllers", Name: "Game controllers", Pkgs: []string{"xpadneo-dkms", "game-devices-udev"}, Def: true,
			Sub: i18n.T("wireless Xbox pads + controller access rules")},

		{ID: "vm", Name: "Virtual machines", Pkgs: []string{"qemu-desktop", "edk2-ovmf", "virglrenderer"}, Def: true, Group: i18n.T("System services"),
			Sub: i18n.T("the windowed VM behind Ryoku Settings > GPU > Machine")},
		{ID: "docker", Name: "Docker", Pkgs: []string{"docker"}, Def: true,
			Sub: i18n.T("the Cobalt engine the file stash downloads through")},
		{ID: "flatpak", Name: "Flatpak", Pkgs: []string{"flatpak"}, Def: true,
			Sub: i18n.T("the portable app channel (the stash installs .flatpak bundles)")},

		{ID: "go", Name: "Go toolchain", Pkgs: []string{"go"}, Def: true, Group: i18n.T("Developer toolchains")},
		{ID: "node", Name: "Node.js + npm", Pkgs: []string{"nodejs", "npm"}, Def: true},
		{ID: "pytools", Name: "Python pip + pipx", Pkgs: []string{"python-pip", "python-pipx"}, Def: true},
		{ID: "mise", Name: "mise", Pkgs: []string{"mise"}, Def: true,
			Sub: i18n.T("language/version manager")},
	}
}

func appRowsForVariant(variant string) []appRow {
	all := appRows()
	if !isVoidVariant(variant) {
		return all
	}
	out := make([]appRow, 0, len(all)-3)
	for _, row := range all {
		switch row.ID {
		// Void's desktop package still requires ryoku-rashin.
		case "localsend", "voxtype", "rashin":
			continue
		}
		out = append(out, row)
	}
	return out
}

// appGroups returns the rows grouped for display: each group's rows in table
// order. A row carrying a Group header opens a new group.
func appGroups() [][]appRow {
	return appGroupsForVariant("")
}

func appGroupsForVariant(variant string) [][]appRow {
	var out [][]appRow
	for _, r := range appRowsForVariant(variant) {
		if r.Group != "" || len(out) == 0 {
			out = append(out, []appRow{r})
			continue
		}
		out[len(out)-1] = append(out[len(out)-1], r)
	}
	return out
}

// appRowByID finds a row by its stable id.
func appRowByID(id string) (appRow, bool) {
	return appRowByIDForVariant("", id)
}

func appRowByIDForVariant(variant, id string) (appRow, bool) {
	for _, r := range appRowsForVariant(variant) {
		if r.ID == id {
			return r, true
		}
	}
	return appRow{}, false
}

// appDefaults is the initial keep map: every row at its shipped default.
func appDefaults() map[string]bool {
	return appDefaultsForVariant("")
}

func appDefaultsForVariant(variant string) map[string]bool {
	m := map[string]bool{}
	for _, r := range appRowsForVariant(variant) {
		m[r.ID] = r.Def
	}
	return m
}

// deselectedPkgs lists the package names the keep map removes from the
// install, in table order. Required rows are never counted, so a stale map
// entry cannot ask the backend to strip a feature package.
func deselectedPkgs(keep map[string]bool) []string {
	return deselectedPkgsForVariant("", keep)
}

func deselectedPkgsForVariant(variant string, keep map[string]bool) []string {
	var out []string
	for _, r := range appRowsForVariant(variant) {
		if r.Req != "" || keep[r.ID] {
			continue
		}
		out = append(out, r.Pkgs...)
	}
	return out
}

// appsSummary is the Review row for the app choice: "all" when nothing was
// removed, else the ids of the dropped rows.
func appsSummary(keep map[string]bool) string {
	return appsSummaryForVariant("", keep)
}

func appsSummaryForVariant(variant string, keep map[string]bool) string {
	var names []string
	for _, r := range appRowsForVariant(variant) {
		if r.Req == "" && !keep[r.ID] {
			names = append(names, r.ID)
		}
	}
	if len(names) == 0 {
		return i18n.T("all")
	}
	return i18n.Tf("minus %s", strings.Join(names, ", "))
}

// appsReviewCell is the Review row for the app choice. The keep map is nil
// until the apps step first loads, which reads as the shipped defaults.
func (m model) appsReviewCell() string {
	if m.keep == nil {
		return i18n.T("all")
	}
	return appsSummaryForVariant(m.variant, m.keep)
}

// selectedApps is the keep map, with the shipped defaults standing in for a
// wizard that never visited the apps step (a scripted handoff keeps every app).
func (m model) selectedApps() map[string]bool {
	if m.keep == nil {
		return appDefaultsForVariant(m.variant)
	}
	return m.keep
}
