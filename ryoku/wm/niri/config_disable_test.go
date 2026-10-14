package main

import (
	"slices"
	"testing"
)

// A bind the user switched off must not reach the emitted config, and a family
// switched off must take all ten members with it: the per-member lookup reads
// the concrete chord, so the stored placeholder alone would match none of them.
func TestDisabledBindsAreNotEmitted(t *testing.T) {
	before := emittedChords(niriStore{})
	if len(before) == 0 {
		t.Fatal("no binds emitted from an empty store; the fixture says nothing")
	}

	after := emittedChords(niriStore{KeybindDisabled: []string{"SUPER + Q", "SUPER + {n}"}})
	for _, gone := range []string{"Super+Q", "Super+1", "Super+5", "Super+0"} {
		if slices.Contains(after, gone) {
			t.Errorf("%q survived being switched off", gone)
		}
		if !slices.Contains(before, gone) {
			t.Errorf("%q was not emitted to begin with, so the test proves nothing about it", gone)
		}
	}
	if len(after) >= len(before) {
		t.Errorf("switching binds off emitted %d chords, was %d: nothing was dropped", len(after), len(before))
	}
}
