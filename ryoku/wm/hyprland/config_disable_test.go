package main

import (
	"strings"
	"testing"
)

// A switched-off bind is released at the chord it actually holds. binds.lua has
// already registered the shipped chord by the time this block runs, and K() has
// already swapped a rebound one, so unbinding the stored default would miss a
// bind the user had moved and leave it live.
func TestDisabledBindIsReleasedAtItsEffectiveChord(t *testing.T) {
	o := Overrides{
		KeybindRebinds:  map[string]string{"SUPER + W": "SUPER + ALT + W"},
		KeybindDisabled: []string{"SUPER + W", "SUPER + Q"},
	}
	got := genUnbinds(o)
	for _, want := range []string{`hl.unbind("SUPER + ALT + W")`, `hl.unbind("SUPER + Q")`} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %s in:\n%s", want, got)
		}
	}
	if strings.Contains(got, `hl.unbind("SUPER + W")`) {
		t.Errorf("released the shipped chord, not the one the bind holds:\n%s", got)
	}
}

// A family is one stored entry standing for ten chords, so switching it off has
// to release all ten and both number-pad faces of each.
func TestDisabledFamilyReleasesEveryMember(t *testing.T) {
	got := genUnbinds(Overrides{KeybindDisabled: []string{"SUPER + KP_{n}"}})
	for _, want := range []string{`hl.unbind("SUPER + KP_1")`, `hl.unbind("SUPER + KP_0")`, `hl.unbind("SUPER + KP_End")`} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %s in:\n%s", want, got)
		}
	}
}

// Unbinds and KeybindDisabled are separate lists on purpose, and an entry in
// both must still produce one line: Hyprland's unbind drops a single bind per
// call, so a second call would take a different bind off the same chord.
func TestDisabledAndImportedUnbindEmitOnce(t *testing.T) {
	o := Overrides{Unbinds: []string{"SUPER + D"}, KeybindDisabled: []string{"SUPER + D"}}
	if n := strings.Count(genUnbinds(o), `hl.unbind("SUPER + D")`); n != 1 {
		t.Fatalf("emitted the same unbind %d times, want 1:\n%s", n, genUnbinds(o))
	}
}
