package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

func desktopStore(t *testing.T, home string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(home, ".config/ryoku/desktop.json"))
	if err != nil {
		t.Fatal(err)
	}
	var root map[string]any
	if err := json.Unmarshal(data, &root); err != nil {
		t.Fatal(err)
	}
	return root
}

func desktopInput(t *testing.T, root map[string]any) map[string]any {
	t.Helper()
	desktop, ok := root["desktop"].(map[string]any)
	if !ok {
		t.Fatalf("desktop settings = %#v", root["desktop"])
	}
	input, ok := desktop["input"].(map[string]any)
	if !ok {
		t.Fatalf("desktop input settings = %#v", desktop["input"])
	}
	return input
}

func TestSeedDesktopKeymapMergesNeutralStore(t *testing.T) {
	t.Run("absent store", func(t *testing.T) {
		home := t.TempDir()
		e := &engine{f: &facts{
			homeDir: home, kbLayout: "fr", kbVariant: "azerty", kbOptions: "ctrl:nocaps", kbSource: "GNOME",
		}, p: &plan{}}
		if err := seedDesktopKeymap(e); err != nil {
			t.Fatal(err)
		}
		input := desktopInput(t, desktopStore(t, home))
		if input["kbLayout"] != "fr" || input["kbVariant"] != "azerty" || input["kbOptions"] != "ctrl:nocaps" {
			t.Fatalf("seeded input = %#v", input)
		}
	})

	t.Run("unrelated settings survive", func(t *testing.T) {
		home := t.TempDir()
		store := filepath.Join(home, ".config/ryoku/desktop.json")
		if err := os.MkdirAll(filepath.Dir(store), 0o755); err != nil {
			t.Fatal(err)
		}
		before := `{"appearance":{"theme":"sumi"},"desktop":{"apps":{"browser":"firefox"},"input":{"repeatRate":31}}}`
		if err := os.WriteFile(store, []byte(before), 0o644); err != nil {
			t.Fatal(err)
		}
		e := &engine{f: &facts{homeDir: home, kbLayout: "de", kbVariant: "nodeadkeys", kbSource: "KDE"}, p: &plan{}}
		if err := seedDesktopKeymap(e); err != nil {
			t.Fatal(err)
		}
		root := desktopStore(t, home)
		appearance, ok := root["appearance"].(map[string]any)
		if !ok || appearance["theme"] != "sumi" {
			t.Fatalf("appearance settings were lost: %#v", root)
		}
		desktop := root["desktop"].(map[string]any)
		apps, ok := desktop["apps"].(map[string]any)
		if !ok || apps["browser"] != "firefox" {
			t.Fatalf("app settings were lost: %#v", desktop)
		}
		input := desktopInput(t, root)
		if input["repeatRate"] != float64(31) || input["kbLayout"] != "de" {
			t.Fatalf("input settings were not merged: %#v", input)
		}
	})

	t.Run("existing non-us layout wins", func(t *testing.T) {
		home := t.TempDir()
		store := filepath.Join(home, ".config/ryoku/desktop.json")
		if err := os.MkdirAll(filepath.Dir(store), 0o755); err != nil {
			t.Fatal(err)
		}
		before := `{"desktop":{"input":{"kbLayout":"de","kbVariant":"nodeadkeys","kbOptions":"ctrl:nocaps"}}}`
		if err := os.WriteFile(store, []byte(before), 0o644); err != nil {
			t.Fatal(err)
		}
		e := &engine{f: &facts{homeDir: home, kbLayout: "fr", kbSource: "GNOME"}, p: &plan{}}
		if err := seedDesktopKeymap(e); err != nil {
			t.Fatal(err)
		}
		input := desktopInput(t, desktopStore(t, home))
		if input["kbLayout"] != "de" || input["kbVariant"] != "nodeadkeys" || input["kbOptions"] != "ctrl:nocaps" {
			t.Fatalf("existing input was overwritten: %#v", input)
		}
	})

	t.Run("explicit AZERTY overrides", func(t *testing.T) {
		home := t.TempDir()
		store := filepath.Join(home, ".config/ryoku/desktop.json")
		if err := os.MkdirAll(filepath.Dir(store), 0o755); err != nil {
			t.Fatal(err)
		}
		before := `{"desktop":{"input":{"kbLayout":"de","kbVariant":"nodeadkeys","kbOptions":"ctrl:nocaps"}}}`
		if err := os.WriteFile(store, []byte(before), 0o644); err != nil {
			t.Fatal(err)
		}
		e := &engine{f: &facts{homeDir: home, kbLayout: "de", kbSource: "KDE"}, p: &plan{azertyBE: true}}
		if err := seedDesktopKeymap(e); err != nil {
			t.Fatal(err)
		}
		input := desktopInput(t, desktopStore(t, home))
		if input["kbLayout"] != "be" || input["kbVariant"] != "" || input["kbOptions"] != "" {
			t.Fatalf("explicit AZERTY did not override the store: %#v", input)
		}
	})
}
