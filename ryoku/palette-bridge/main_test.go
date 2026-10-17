package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestBridgeWaitsForAPaletteWrittenAfterStart(t *testing.T) {
	palette := filepath.Join(t.TempDir(), "cache", "ryoku", "colors.json")
	hub := newPaletteHub()
	if err := hub.readFile(palette); err == nil {
		t.Fatal("reading a missing palette succeeded")
	}
	go func() { _ = watchPalette(palette, func() error { return hub.readFile(palette) }) }()

	rec := httptest.NewRecorder()
	hub.paletteHandler(rec, httptest.NewRequest(http.MethodGet, "/colors.json", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status before a palette = %d, want 503", rec.Code)
	}

	want := `{"primary":"#C75D2B","surface":"#060607","onSurface":"#EAE2D5"}`
	// rewrite until it lands: the watch is armed only after the watcher has
	// created the directory, and a write before that goes unseen.
	deadline := time.Now().Add(5 * time.Second)
	for string(hub.snapshot().data) != want {
		if time.Now().After(deadline) {
			t.Fatalf("palette not picked up: %q", hub.snapshot().data)
		}
		if err := os.MkdirAll(filepath.Dir(palette), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(palette, []byte(want), 0o644); err != nil {
			t.Fatal(err)
		}
		time.Sleep(20 * time.Millisecond)
	}
}
