package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

// osd.go feeds the brightness OSD. The volume and mic OSDs read PipeWire
// directly in QML, where Ryoku already owns the audio graph, so their change
// events and value are observable without the daemon. Brightness has no such
// QML-observable source: the media keys and the `brightness` verb both drive
// ryoku-cmd-brightness straight to the backlight, so the daemon watches the
// primary backlight and pushes a fraction plus a monotonically rising sequence
// to the `osd` topic. QML shows the brightness OSD when the sequence advances
// and binds `value` to the slider; the bucket->icon mapping lives once in QML
// beside the volume and mic buckets. Contract 12 sec 3, sec 9.

type osdState struct {
	topic *stateTopic
	seq   int
}

// backlightLevelPath is where the last user-set panel level lives across
// reboots. The kernel drives every backlight to its hardware default at boot
// and nothing else persists the level, so a plain reboot erased it (#199).
// The watcher below is the one place every writer (media keys, the slider,
// the brightness verb) converges, so it owns both halves: save on change,
// restore before the session's first read.
func backlightLevelPath() string {
	return filepath.Join(stateDir(), "ryoku", "backlight")
}

// saveBacklight records the raw sysfs level. Best-effort: a read-only state
// dir costs persistence, not the session.
func saveBacklight(level int) {
	dir := filepath.Join(stateDir(), "ryoku")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return
	}
	_ = os.WriteFile(backlightLevelPath(), []byte(strconv.Itoa(level)), 0o644)
}

// restoreBacklight pushes the saved level onto the device before the watcher
// opens it, so the first published value is the restored one and the OSD and
// sliders agree with the screen. A level outside [1,max] (the panel changed
// shape, the file is stale) is dropped rather than trusted; a device that
// rejects the write (no seat ACL on an unusual box) is left at the kernel's
// value instead of fought.
func restoreBacklight(dev string, max int) {
	if max <= 0 {
		return
	}
	b, err := os.ReadFile(backlightLevelPath())
	if err != nil {
		return
	}
	want, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil || want < 1 || want > max {
		return
	}
	if cur, ok := readSysInt(filepath.Join(dev, "brightness")); ok && cur == want {
		return
	}
	_ = os.WriteFile(filepath.Join(dev, "brightness"), []byte(strconv.Itoa(want)), 0o644)
}

// backlightDevice picks the primary backlight: the first entry under
// /sys/class/backlight. Absent (a desktop with no panel) means no watcher, so
// the brightness OSD simply never fires, matching the reference where a missing
// brightness device produces no update. Mirrors brightness_service().primary.
func backlightDevice() string {
	const base = "/sys/class/backlight"
	ents, err := os.ReadDir(base)
	if err != nil || len(ents) == 0 {
		return ""
	}
	return filepath.Join(base, ents[0].Name())
}

// readSysInt reads a single integer sysfs attribute.
func readSysInt(path string) (int, bool) {
	b, err := os.ReadFile(path)
	if err != nil {
		return 0, false
	}
	n, err := strconv.Atoi(strings.TrimSpace(string(b)))
	if err != nil {
		return 0, false
	}
	return n, true
}

// startOsd registers the `osd` topic and, when a backlight exists, starts the
// watcher goroutine that republishes on every brightness change.
func (d *daemon) startOsd() {
	o := &osdState{topic: d.registerTopic("osd")}
	o.publish(0)
	if dev := backlightDevice(); dev != "" {
		go o.watchBacklight(dev)
	}
}

// publish writes the current osd frame. The topic drops a byte-identical frame,
// so republishing an unchanged value never wakes a QML binding.
func (o *osdState) publish(value float64) {
	frame, _ := json.Marshal(map[string]any{
		"brightness": map[string]any{"seq": o.seq, "value": value},
	})
	o.topic.publish(frame)
}

// watchBacklight blocks in poll(2) on the backlight's actual_brightness sysfs
// attribute, which the kernel wakes with POLLPRI on every brightness change
// (media keys, the brightness verb, or anything else). Each wake recomputes the
// fraction, bumps the sequence, and republishes. The first read is the current
// value and does NOT bump the sequence, so a fresh subscriber never flashes the
// OSD at startup. Reading the attribute after each poll re-arms the notify.
func (o *osdState) watchBacklight(dev string) {
	maxb, ok := readSysInt(filepath.Join(dev, "max_brightness"))
	if !ok || maxb <= 0 {
		return
	}
	restoreBacklight(dev, maxb)
	fd, err := unix.Open(filepath.Join(dev, "actual_brightness"), unix.O_RDONLY, 0)
	if err != nil {
		return
	}
	defer unix.Close(fd)

	buf := make([]byte, 32)
	if cur, ok := readActual(fd, buf); ok {
		o.publish(float64(cur) / float64(maxb))
	}
	for {
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLPRI | unix.POLLERR}}
		n, err := unix.Poll(fds, -1)
		if err != nil {
			if err == unix.EINTR {
				continue
			}
			return
		}
		if n == 0 {
			continue
		}
		cur, ok := readActual(fd, buf)
		if !ok {
			continue
		}
		o.seq++
		o.publish(float64(cur) / float64(maxb))
		// Persist the writable `brightness` attribute, not the polled one:
		// amdgpu reports actual_brightness on its own hardware scale, so a
		// saved raw value would restore to the wrong level.
		if raw, ok := readSysInt(filepath.Join(dev, "brightness")); ok {
			saveBacklight(raw)
		}
	}
}

// readActual reads the backlight level via pread at offset 0, which both fetches
// the value and clears the pending poll condition on the sysfs file.
func readActual(fd int, buf []byte) (int, bool) {
	n, err := unix.Pread(fd, buf, 0)
	if err != nil || n <= 0 {
		return 0, false
	}
	v, err := strconv.Atoi(strings.TrimSpace(string(buf[:n])))
	if err != nil {
		return 0, false
	}
	return v, true
}
