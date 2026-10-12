package main

import (
	"slices"
	"strings"
	"testing"

	wm "ryoku-wm"
)

func TestFedoraNoticeFollowsWelcome(t *testing.T) {
	t.Setenv("RYOKU_KB_PRESET", "")
	flow := stepsForVariant(variantFedora)
	if flow[0].key != "fedora-notice" {
		t.Fatalf("Fedora flow starts with %q, want fedora-notice", flow[0].key)
	}
	if flowIndex(stepsForVariant(variantVoid), "fedora-notice") >= 0 || flowIndex(stepsForVariant("plain"), "fedora-notice") >= 0 {
		t.Fatal("the Fedora notice leaked into another edition")
	}
	text := strings.Join(flow[0].desc, "\n")
	for _, want := range []string{
		"This Fedora edition is experimental.",
		"Available window managers: hyprland, niri.",
		"network connection",
		"Secure Boot can stay on",
		"nouveau",
		"no snapshot boot menu",
		"Wayfire is unavailable: Fedora ships Wayfire 0.10.1",
	} {
		if !strings.Contains(text, want) {
			t.Fatalf("Fedora notice is missing %q: %v", want, flow[0].desc)
		}
	}
}

func TestFedoraCompositorsComeFromItsTable(t *testing.T) {
	flow := stepsForVariant(variantFedora)
	m := model{variant: variantFedora, flow: flow, idx: flowIndex(flow, "compositor"), picks: map[string]string{"compositor": wm.ProviderHyprland}}
	m.loadStep()
	if m.pick.disabled[wm.ProviderHyprland] || m.pick.disabled[wm.ProviderNiri] {
		t.Fatalf("Fedora disabled a shipped compositor: %v", m.pick.disabled)
	}
	for _, it := range m.pick.items {
		if it.key == "wayfire" && !m.pick.disabled["wayfire"] {
			t.Fatal("Fedora offers Wayfire as selectable")
		}
	}
}

func TestFedoraAllowsSecureBootAndKeepsBIOSBlocked(t *testing.T) {
	fedora := reviewModel()
	fedora.variant, fedora.hwSecureBoot = variantFedora, true
	if reason := fedora.reviewBlockReason(); reason != "" {
		t.Fatalf("Fedora with Secure Boot on is blocked: %q", reason)
	}
	if body := stripSGR(fedora.infoBody(100)); strings.Contains(body, "Limine is unsigned") {
		t.Fatalf("Fedora hardware card asks to disable Secure Boot:\n%s", body)
	}

	arch := reviewModel()
	arch.hwSecureBoot = true
	if !strings.Contains(arch.reviewBlockReason(), "Secure Boot") {
		t.Fatal("Arch with Secure Boot on is no longer blocked")
	}

	fedora.hwBIOS = true
	if !fedora.biosBlocked() {
		t.Fatal("Fedora accepts legacy BIOS")
	}
	if body := stripSGR(fedora.infoBody(100)); !strings.Contains(body, "UEFI-only") {
		t.Fatalf("Fedora BIOS refusal does not explain itself:\n%s", body)
	}
}

func TestFedoraInstallsOnlineWithItsOwnESP(t *testing.T) {
	if _, ok := offlineRepo(variantFedora); ok {
		t.Fatal("Fedora reports an offline package set")
	}
	m := reviewModel()
	m.variant, m.espFreeKiB = variantFedora, 1<<20
	if got := m.espMode(); got != "dedicated" {
		t.Fatalf("Fedora alongside ESP mode = %q, want dedicated even with room on the existing ESP", got)
	}
	env := m.installEnv()
	for _, want := range []string{"RYOKU_ESP_MODE=dedicated", "RYOKU_ONLINE=1", "RYOKU_FIRMWARE_MODE=uefi"} {
		if !envHas(env, want) {
			t.Fatalf("Fedora backend env is missing %s: %v", want, env)
		}
	}
	for _, value := range env {
		if strings.HasPrefix(value, "RYOKU_OFFLINE_REPO=") {
			t.Fatalf("Fedora hands the backend an offline repo: %q", value)
		}
	}

	m.netOnline = false
	if !strings.Contains(m.reviewBlockReason(), "No internet connection") {
		t.Fatalf("Fedora without network is not blocked: %q", m.reviewBlockReason())
	}
}

func TestFedoraHidesAppsItsBackendNeverInstalls(t *testing.T) {
	rows := appRowsForVariant(variantFedora)
	for _, row := range rows {
		for _, hidden := range unshippedApps[variantFedora] {
			if row.ID == hidden {
				t.Fatalf("Fedora offers %q", hidden)
			}
		}
	}
	groups := appGroupsForVariant(variantFedora)
	var headers []string
	for _, group := range groups {
		if group[0].Group == "" {
			t.Fatalf("Fedora app group has no header: %+v", group)
		}
		headers = append(headers, group[0].Group)
	}
	joined := strings.Join(headers, "|")
	if !strings.Contains(joined, "Media & tools") || strings.Contains(joined, "Developer toolchains") {
		t.Fatalf("Fedora app group headers = %v", headers)
	}
	for _, variant := range []string{variantFedora, variantVoid} {
		if !slices.ContainsFunc(appRowsForVariant(variant), func(row appRow) bool { return row.ID == "pavucontrol" }) {
			t.Fatalf("%s hides pavucontrol, which ryoku doctor delivers unless it is dropped here", variant)
		}
	}
	if got, want := len(appRowsForVariant(variantVoid)), len(appRows())-len(unshippedApps[variantVoid]); got != want {
		t.Fatalf("Void app rows = %d, want %d", got, want)
	}
}

func TestFedoraNamesGRUBNotLimine(t *testing.T) {
	picks := map[string]string{"hostname": "ryoku", "username": "you", "profile": "vm", "encryption": "off", "timezone": "UTC"}
	if done := stripSGR((model{variant: variantFedora, picks: picks}).viewDone()); strings.Contains(done, "Limine") {
		t.Fatalf("Fedora done card promises a Limine boot menu:\n%s", done)
	}
	phases := installSteps(variantFedora)
	if last := phases[len(phases)-1]; !strings.Contains(last, "GRUB") {
		t.Fatalf("Fedora bootloader phase = %q, want GRUB", last)
	}
}
