package updater

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// A restore runs from a look boot, the way limine-snapper-restore does on
// Arch: the user boots the snapshot from the menu, sees that it is the one, and
// runs `sudo ryoku boot-menu restore`. The current root subvolume is kept as
// <root>.broken-<time>, a writable snapshot of the booted one takes its name,
// and the next boot (only that one) starts the restored root with the kernel
// copy the look boot runs. /boot is not part of a snapshot, so that first boot
// runs `ryoku boot-menu restored` (ryoku-snapshot-restored.service), which
// brings Fedora's boot entries in line with the kernels the restored root has.
const (
	restoredEntryID = "ryoku-restored"
	// where the look boot's initramfs hook mounts the snapshot it shows.
	previewLower = "/run/ryoku/preview/lower"
	btrfsTop     = "/run/ryoku/btrfs-top"
	// a set-aside root is deleted this long after a restore; the newest one
	// is always kept.
	brokenRootKeep = 14 * 24 * time.Hour
)

// restoredFlag lives inside the root subvolume, so only the restored root
// sees it; the restore writes it there before that root ever boots.
const restoredFlag = "/var/lib/ryoku/snapshot-restored"

var fstabFile = "/etc/fstab"

func restoreSnapshot() error {
	snap := cmdlineValue(readText(procCmdline), "rd.ryoku.preview")
	if snap == "" {
		return errors.New(i18n.T("this boot is not a snapshot look boot: reboot, open Ryoku snapshots in the boot menu, pick the snapshot, then run this again"))
	}
	if !safeSubvolPath(snap) || !strings.HasSuffix(snap, "/snapshot") {
		return fmt.Errorf(i18n.T("refusing snapshot path %q"), snap)
	}
	mounts := parseMountInfo(readText(mountInfo))
	lower, ok := mounts[previewLower]
	if !ok || lower.fstype != "btrfs" {
		return fmt.Errorf(i18n.T("the snapshot is not mounted at %s; this boot cannot restore it"), previewLower)
	}
	rootSubvol := fstabRootSubvol(readText(fstabFile))
	if rootSubvol == "" || strings.Contains(rootSubvol, "/") || !safeSubvolPath(rootSubvol) {
		return fmt.Errorf(i18n.T("%s names no root subvolume this can replace"), fstabFile)
	}
	out, err := sys.RunOut("uname", "-r")
	kver := strings.TrimSpace(out)
	if err != nil || !sys.Exists(filepath.Join(snapshotKernelDir(), kver, "initramfs.img")) {
		return fmt.Errorf(i18n.T("kernel %s has no copy under %s to boot the restored system with"), kver, snapshotKernelDir())
	}
	boot, ok := mounts[bootDir]
	if !ok {
		return errors.New(i18n.T("/boot is not mounted"))
	}
	uuid, err := blockUUID(boot.source)
	if err != nil {
		return err
	}
	opts, flags := baseSnapshotOptions(readText(procCmdline))
	layout := menuLayout{bootUUID: uuid, options: opts, rootflags: flags}

	top, cleanup, err := mountBtrfsTop(lower.source)
	if err != nil {
		return err
	}
	defer cleanup()
	if !isDir(filepath.Join(top, snap)) || !isDir(filepath.Join(top, rootSubvol)) {
		return fmt.Errorf(i18n.T("%s or %s is missing from the btrfs top level; nothing was changed"), snap, rootSubvol)
	}
	broken := rootSubvol + ".broken-" + time.Now().UTC().Format("20060102-150405")
	if err := os.Rename(filepath.Join(top, rootSubvol), filepath.Join(top, broken)); err != nil {
		return fmt.Errorf(i18n.T("setting the current root aside: %w; nothing was changed"), err)
	}
	if err := sys.Run("btrfs", "subvolume", "snapshot", filepath.Join(top, snap), filepath.Join(top, rootSubvol)); err != nil {
		_ = os.Rename(filepath.Join(top, broken), filepath.Join(top, rootSubvol))
		return fmt.Errorf(i18n.T("snapshotting %s failed, the current root is back: %w"), snap, err)
	}
	if err := writeFileAtomic(filepath.Join(top, rootSubvol, restoredFlag), snap+" "+broken+"\n", 0o644); err != nil {
		return err
	}
	menu := readText(snapshotMenuCfg()) + renderRestoredEntry(layout, rootSubvol, kver)
	if err := writeFileAtomic(snapshotMenuCfg(), menu, 0o644); err != nil {
		return err
	}
	if err := sys.Run("grub2-reboot", restoredEntryID); err != nil {
		return fmt.Errorf(i18n.T("the root is restored, but the next boot could not be pointed at it: %w"), err)
	}
	fmt.Printf(i18n.T("Restored %s. The system it replaced is kept as %s for two weeks.\n"), snap, broken)
	fmt.Println(i18n.T("Reboot now to start the restored system."))
	return nil
}

// renderRestoredEntry boots the restored root once, with the kernel copy the
// look boot ran: the root's own kernels get their boot entries only once it
// runs. `ryoku boot-menu sync` drops it again.
func renderRestoredEntry(l menuLayout, rootSubvol, kver string) string {
	var b strings.Builder
	fmt.Fprintf(&b, "menuentry 'Ryoku: restored system' --id %s {\n", restoredEntryID)
	writeKernelLines(&b, "  ", l, kver, l.entryOptions(rootSubvol, ""))
	b.WriteString("}\n")
	return b.String()
}

// snapshotRestored runs on the first boot of a restored root. Fedora's BLS
// entries for kernels the restored root has no modules for are removed, the
// restored root's kernels get entries (kernel-install also builds their
// initramfs), and the kernel running now, the one the snapshot booted with,
// becomes the default.
func snapshotRestored() error {
	what := strings.Fields(readText(restoredFlag))
	if len(what) < 2 {
		return nil
	}
	fmt.Printf(i18n.T("boot menu: this root was restored from %s; the one it replaced is %s\n"), what[0], what[1])
	mid := strings.TrimSpace(readText("/etc/machine-id"))
	for _, kver := range blsKernels(blsDir, mid) {
		if !sys.Exists(filepath.Join(modulesDir, kver)) {
			_ = sys.Run("kernel-install", "remove", kver)
		}
	}
	modules, _ := os.ReadDir(modulesDir)
	for _, m := range modules {
		kver := m.Name()
		img := filepath.Join(modulesDir, kver, "vmlinuz")
		if sys.Exists(img) && !sys.Exists(filepath.Join(blsDir, mid+"-"+kver+".conf")) {
			_ = sys.Run("kernel-install", "add", kver, img)
		}
	}
	if out, err := sys.RunOut("uname", "-r"); err == nil {
		if img := filepath.Join(bootDir, "vmlinuz-"+strings.TrimSpace(out)); sys.Exists(img) {
			_ = sys.Run("grubby", "--set-default", img)
		}
	}
	_ = os.Remove(restoredFlag)
	_ = writeNotice(bootNotice{Action: "snapshot-restored", Snapshot: what[0],
		Detail: fmt.Sprintf(i18n.T("the system was restored from %s. The root it replaced is kept as %s for two weeks."), what[0], what[1]),
		At:     now()})
	return syncSnapshotMenu()
}

// blsKernels lists the kernel versions that have a plain Fedora BLS entry:
// no rescue image, and no debug or other variant twins.
func blsKernels(dir, mid string) []string {
	var out []string
	matches, _ := filepath.Glob(filepath.Join(dir, mid+"-*.conf"))
	for _, m := range matches {
		kver := strings.TrimSuffix(strings.TrimPrefix(filepath.Base(m), mid+"-"), ".conf")
		if strings.HasPrefix(kver, "0-rescue") || strings.Contains(kver, "~") {
			continue
		}
		out = append(out, kver)
	}
	return out
}

// pruneBrokenRoots deletes the roots earlier restores set aside once they are
// older than brokenRootKeep, keeping the newest regardless.
func pruneBrokenRoots(rootSubvol string) {
	root, ok := parseMountInfo(readText(mountInfo))["/"]
	if !ok {
		return
	}
	top, cleanup, err := mountBtrfsTop(root.source)
	if err != nil {
		return
	}
	defer cleanup()
	matches, _ := filepath.Glob(filepath.Join(top, rootSubvol+".broken-*"))
	sort.Strings(matches)
	for i, m := range matches {
		if i == len(matches)-1 {
			break
		}
		stamp := strings.TrimPrefix(filepath.Base(m), rootSubvol+".broken-")
		at, err := time.Parse("20060102-150405", stamp)
		if err != nil || time.Since(at) < brokenRootKeep {
			continue
		}
		// -R: systemd creates var/lib/portables as a subvolume inside the root
		if err := sys.Run("btrfs", "subvolume", "delete", "-R", m); err == nil {
			fmt.Printf(i18n.T("boot menu: deleted %s, set aside by a restore on %s\n"), filepath.Base(m), at.Format("2006-01-02"))
		}
	}
}

// mountBtrfsTop mounts the top level of a btrfs device privately under
// /run/ryoku, where the root subvolume, the snapshots and set-aside roots sit
// side by side.
func mountBtrfsTop(dev string) (string, func(), error) {
	if err := os.MkdirAll(btrfsTop, 0o700); err != nil {
		return "", nil, err
	}
	if err := sys.Run("mount", "-t", "btrfs", "-o", "subvolid=5", dev, btrfsTop); err != nil {
		return "", nil, fmt.Errorf(i18n.T("mounting the btrfs top level: %w"), err)
	}
	return btrfsTop, func() { _ = sys.Run("umount", btrfsTop) }, nil
}

// cmdlineValue is the value of key=... on a kernel command line, or "".
func cmdlineValue(cmdline, key string) string {
	for _, tok := range strings.Fields(cmdline) {
		if v, ok := strings.CutPrefix(tok, key+"="); ok {
			return v
		}
	}
	return ""
}

// fstabRootSubvol is the subvolume the fstab entry for / mounts.
func fstabRootSubvol(fstab string) string {
	for _, line := range strings.Split(fstab, "\n") {
		f := strings.Fields(line)
		if len(f) < 4 || strings.HasPrefix(f[0], "#") || f[1] != "/" {
			continue
		}
		for _, o := range strings.Split(f[3], ",") {
			if v, ok := strings.CutPrefix(o, "subvol="); ok {
				return strings.Trim(v, "/")
			}
		}
	}
	return ""
}

// safeSubvolPath accepts a relative btrfs path of plain name characters, the
// shape snapper and Fedora's installer give subvolumes.
func safeSubvolPath(p string) bool {
	if p == "" || strings.HasPrefix(p, "/") || strings.Contains(p, "..") {
		return false
	}
	for _, r := range p {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || strings.ContainsRune("._/-", r)) {
			return false
		}
	}
	return true
}

func isDir(path string) bool {
	fi, err := os.Stat(path)
	return err == nil && fi.IsDir()
}
