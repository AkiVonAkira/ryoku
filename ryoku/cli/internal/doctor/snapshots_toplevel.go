package doctor

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"ryoku-cli/internal/sys"
	i18n "ryoku-i18n"
)

// On Fedora the snapshots live in their own top-level btrfs subvolume, mounted
// at /.snapshots beside the root subvolume rather than nested inside it. A
// whole-system restore swaps the root subvolume out; snapshots nested in it
// would leave with the old root.
const (
	topLevelSnapshotsSubvol = ".snapshots"
	btrfsTopMount           = "/run/ryoku/btrfs-top"
	fstabPath               = "/etc/fstab"
)

// snapshotsFstabLine derives the /.snapshots entry from the btrfs root's: the
// same device and options with its own subvolume. It is "" when fstab has no
// btrfs root that names a subvolume, a layout this cannot extend.
func snapshotsFstabLine(fstab string) string {
	for _, line := range strings.Split(fstab, "\n") {
		f := strings.Fields(line)
		if len(f) < 4 || strings.HasPrefix(f[0], "#") || f[1] != "/" || f[2] != "btrfs" {
			continue
		}
		var opts []string
		named := false
		for _, o := range strings.Split(f[3], ",") {
			switch {
			case strings.HasPrefix(o, "subvol="):
				opts = append(opts, "subvol="+topLevelSnapshotsSubvol)
				named = true
			case strings.HasPrefix(o, "subvolid="):
			default:
				opts = append(opts, o)
			}
		}
		if !named {
			return ""
		}
		return strings.Join([]string{f[0], "/.snapshots", "btrfs", strings.Join(opts, ","), "0", "0"}, " ")
	}
	return ""
}

// fstabMounts reports whether fstab has an active entry for target.
func fstabMounts(fstab, target string) bool {
	for _, line := range strings.Split(fstab, "\n") {
		f := strings.Fields(line)
		if len(f) >= 2 && !strings.HasPrefix(f[0], "#") && f[1] == target {
			return true
		}
	}
	return false
}

// createTopLevelSnapshots creates the top-level snapshots subvolume, adds its
// fstab entry, and mounts it at /.snapshots. A subvolume or fstab entry an
// earlier run left behind is adopted, not recreated.
func createTopLevelSnapshots() error {
	raw, err := os.ReadFile(fstabPath)
	if err != nil {
		return err
	}
	fstab := string(raw)
	line := snapshotsFstabLine(fstab)
	if line == "" {
		return fmt.Errorf(i18n.T("the root entry in %s names no btrfs subvolume"), fstabPath)
	}
	dev, err := sys.RunOut("findmnt", "-nvo", "SOURCE", "/")
	if dev = strings.TrimSpace(dev); err != nil || dev == "" {
		return fmt.Errorf(i18n.T("no device for the root filesystem"))
	}
	if err := sys.Run("sudo", "mkdir", "-p", btrfsTopMount); err != nil {
		return err
	}
	if err := sys.Run("sudo", "mount", "-t", "btrfs", "-o", "subvolid=5", dev, btrfsTopMount); err != nil {
		return fmt.Errorf(i18n.T("mounting the btrfs top level: %w"), err)
	}
	sub := filepath.Join(btrfsTopMount, topLevelSnapshotsSubvol)
	if sys.Run("sudo", "test", "-d", sub) != nil {
		err = sys.Run("sudo", "btrfs", "subvolume", "create", sub)
	}
	_ = sys.Run("sudo", "umount", btrfsTopMount)
	if err != nil {
		return fmt.Errorf(i18n.T("creating the %s subvolume: %w"), topLevelSnapshotsSubvol, err)
	}
	if !fstabMounts(fstab, "/.snapshots") {
		if !strings.HasSuffix(fstab, "\n") {
			fstab += "\n"
		}
		if err := writeRootFile(fstabPath, fstab+line+"\n", "0644"); err != nil {
			return fmt.Errorf(i18n.T("adding /.snapshots to %s: %w"), fstabPath, err)
		}
		_ = sys.Run("sudo", "restorecon", fstabPath)
		_ = sys.Run("sudo", "systemctl", "daemon-reload")
	}
	if err := sys.Run("sudo", "mkdir", "-p", "/.snapshots"); err != nil {
		return err
	}
	if err := sys.Run("sudo", "mount", "/.snapshots"); err != nil {
		return fmt.Errorf(i18n.T("mounting /.snapshots: %w"), err)
	}
	_ = sys.Run("sudo", "restorecon", "-R", "/.snapshots")
	return nil
}
