package host

import (
	"fmt"
	"os"
	"strings"

	i18n "ryoku-i18n"
)

const snapshotsUnavailableReason = "Snapshots are not available on this host, so updates cannot be rolled back."

// Snapshots reports whether this host provides Ryoku's snapper-based safety net.
func (a *App) Snapshots() (supported bool, reason string) {
	manager, err := a.PackageManager()
	if err == nil && (manager == Pacman || manager == XBPS || manager == DNF) {
		return true, ""
	}
	return false, i18n.T(snapshotsUnavailableReason)
}

func (a *App) Snapshot(args []string) int {
	supported, reason := a.Snapshots()
	if !supported {
		if reason != "" {
			fmt.Fprintln(a.cfg.Stdout, reason)
		}
		return ExitNotProvided
	}
	if len(args) == 0 {
		return ExitOK
	}
	if len(args) != 2 || args[0] != "create" || strings.TrimSpace(args[1]) == "" {
		return ExitUsage
	}
	if !a.cfg.Runner.LookPath("snapper") {
		fmt.Fprintln(a.cfg.Stderr, i18n.T("snapper is not installed"))
		return ExitAbsent
	}
	if info, err := os.Stat(a.cfg.SnapperRootConfig); err != nil || info.IsDir() {
		fmt.Fprintln(a.cfg.Stderr, i18n.T("snapper's root configuration is not available"))
		return ExitAbsent
	}
	result := a.run("snapper", "-c", "root", "create", "-c", "number", "--description", args[1])
	if result.Code != ExitOK {
		return commandExit(result)
	}
	return commandExit(a.run("snapper", "-c", "root", "cleanup", "number"))
}
