package doctor

import (
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// The Fedora-only lineage before the current boot menu left state behind that
// no package owns, so an upgrade to the current packages does not take it
// away:
//
//   - its 95-ryoku-console.install plugin twinned every kernel's BLS entry as
//     <id>-<kver>~ryokuconsole.conf. The plugin is gone, so the twins stay in
//     GRUB's menu for good and no new kernel gets one.
//   - its %post disabled Fedora's grub-boot-success.timer for every user, which
//     keeps GRUB from hiding its menu after a good boot and from counting a
//     failed one. That is restored once, so a later choice to disable it
//     stands.
const (
	legacyConsoleSuffix = "~ryokuconsole"
	legacyConsolePlugin = "/usr/lib/kernel/install.d/95-ryoku-console.install"
	bootSuccessTimer    = "grub-boot-success.timer"
	bootSuccessUnit     = "/usr/lib/systemd/user/grub-boot-success.timer"
	bootSuccessMarker   = "/var/lib/ryoku/migrations/grub-boot-success-timer"
	legacyBLSDir        = "/boot/loader/entries"
)

// legacyBootState is what the reconciler looks at, lifted to a value so the
// plan is testable without a real /boot or systemd.
type legacyBootState struct {
	pluginPresent bool
	entriesRead   bool
	entries       []string
	timerShipped  bool
	timerEnabled  bool
	timerMigrated bool
}

type legacyBootPlan struct {
	removeTwins []string
	enableTimer bool
	markTimer   bool
}

func (p legacyBootPlan) empty() bool {
	return len(p.removeTwins) == 0 && !p.enableTimer && !p.markTimer
}

// planLegacyBoot picks what to undo. Twins are left alone while the old plugin
// is still installed, since it would only write them again.
func planLegacyBoot(s legacyBootState) legacyBootPlan {
	var p legacyBootPlan
	if !s.pluginPresent && s.entriesRead {
		for _, e := range s.entries {
			if strings.HasSuffix(filepath.Base(e), legacyConsoleSuffix+".conf") {
				p.removeTwins = append(p.removeTwins, e)
			}
		}
	}
	if s.timerShipped && !s.timerMigrated {
		p.enableTimer = !s.timerEnabled
		p.markTimer = true
	}
	return p
}

// legacy boot probes, variables so tests stub them.
var (
	legacyBLSEntries = func() ([]string, bool) {
		out, err := sys.RunOut("sudo", "-n", "find", legacyBLSDir, "-maxdepth", "1", "-name", "*.conf")
		if err != nil {
			return nil, false
		}
		return strings.Fields(out), true
	}
	globalTimerEnabled = func() bool {
		return sys.Run("systemctl", "--global", "is-enabled", "--quiet", bootSuccessTimer) == nil
	}
)

func gatherLegacyBootState() legacyBootState {
	entries, read := legacyBLSEntries()
	return legacyBootState{
		pluginPresent: sys.Exists(legacyConsolePlugin),
		entriesRead:   read,
		entries:       entries,
		timerShipped:  sys.Exists(bootSuccessUnit),
		timerEnabled:  globalTimerEnabled(),
		timerMigrated: sys.Exists(bootSuccessMarker),
	}
}

func reconcileFedoraLegacyBoot(checkOnly bool) recResult {
	plan := planLegacyBoot(gatherLegacyBootState())
	if plan.empty() {
		return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
	}
	if checkOnly {
		var found []string
		if len(plan.removeTwins) > 0 {
			found = append(found, i18n.T("Ryoku console boot entries no package keeps up to date"))
		}
		if plan.enableTimer {
			found = append(found, i18n.T("Fedora's grub-boot-success.timer is off for every user"))
		}
		if len(found) == 0 {
			return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
		}
		return wouldRes("%s", strings.Join(found, "; ")).
			withFix(i18n.T("ryoku doctor (removes them and turns the timer back on)"))
	}
	var done []string
	if len(plan.removeTwins) > 0 {
		if err := sys.Sudo(append([]string{"rm", "-f", "--"}, plan.removeTwins...)...); err != nil {
			return failRes(i18n.T("removing the Ryoku console boot entries: %v"), err).
				withFix(i18n.T("sudo rm -f %s/*%s.conf"), legacyBLSDir, legacyConsoleSuffix)
		}
		done = append(done, i18n.T("removed the Ryoku console boot entries"))
	}
	if plan.enableTimer {
		if err := sys.Sudo("systemctl", "--global", "enable", bootSuccessTimer); err != nil {
			return failRes(i18n.T("turning %s back on: %v"), bootSuccessTimer, err).
				withFix(i18n.T("sudo systemctl --global enable %s"), bootSuccessTimer)
		}
		done = append(done, i18n.T("turned Fedora's grub-boot-success.timer back on"))
	}
	if plan.markTimer {
		if err := sys.Sudo("install", "-D", "-m", "0644", "/dev/null", bootSuccessMarker); err != nil {
			return failRes(i18n.T("recording the %s migration: %v"), bootSuccessTimer, err)
		}
	}
	if len(done) == 0 {
		return okRes(i18n.T("no boot-menu leftovers from earlier Fedora packages"))
	}
	return fixedRes("%s", strings.Join(done, "; "))
}
