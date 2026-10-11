package main

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"ryoku-i18n"
	"ryoku-wm"
)

type editionCompositorPlan struct {
	available []string
	omitted   []string
}

func compositorLabel(name string) string {
	if name == "" {
		return ""
	}
	return strings.ToUpper(name[:1]) + name[1:]
}

func parseEditionCompositors(data []byte) (editionCompositorPlan, error) {
	rows := map[string][]string{}
	edition := ""
	header := false
	for lineNo, line := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(line) == "" || strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}
		fields := strings.Split(line, "\t")
		if !header {
			header = true
			if len(fields) != 4 || fields[0] != "arch" || fields[2] != "lanes" || fields[3] != "notes" {
				return editionCompositorPlan{}, fmt.Errorf(i18n.T("package table line %d has an invalid header"), lineNo+1)
			}
			edition = fields[1]
			continue
		}
		if len(fields) != 4 {
			return editionCompositorPlan{}, fmt.Errorf(i18n.T("package table line %d must have four tab-separated columns"), lineNo+1)
		}
		rows[fields[0]] = fields
	}
	if !header {
		return editionCompositorPlan{}, errors.New(i18n.T("package table has no header"))
	}

	var plan editionCompositorPlan
	for _, provider := range wm.Providers() {
		packageName := "ryoku-desktop-" + provider
		row, ok := rows[packageName]
		if ok && row[1] != "-" {
			plan.available = append(plan.available, provider)
			continue
		}
		reason := i18n.Tf("%s is not listed in the %s edition table.", packageName, edition)
		if ok && row[3] != "" {
			reason = row[3]
		}
		plan.omitted = append(plan.omitted, i18n.Tf("%s unavailable: %s", compositorLabel(provider), reason))
	}
	if len(plan.available) == 0 {
		return editionCompositorPlan{}, fmt.Errorf(i18n.T("the %s edition table publishes no compositor variants"), edition)
	}
	return plan, nil
}

func loadEditionCompositors(client httpDoer, d *distro, ref, payload string) (editionCompositorPlan, error) {
	if d == nil || d.id != "fedora" && d.id != "void" {
		return editionCompositorPlan{available: wm.Providers()}, nil
	}
	if payload != "" {
		path := filepath.Join(payload, d.id, "packages", "translations.tsv")
		data, err := os.ReadFile(path)
		if err != nil {
			return editionCompositorPlan{}, fmt.Errorf(i18n.T("read %s compositor choices: %w"), d.name, err)
		}
		return parseEditionCompositors(data)
	}
	url := "https://raw.githubusercontent.com/ryoku-dev/ryoku/" + ref + "/" + d.id + "/packages/translations.tsv"
	resp, err := httpStatusOK(client, http.MethodGet, url)
	if err != nil {
		return editionCompositorPlan{}, fmt.Errorf(i18n.T("read %s compositor choices from %s: %w"), d.name, url, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
	if err != nil {
		return editionCompositorPlan{}, err
	}
	return parseEditionCompositors(data)
}
