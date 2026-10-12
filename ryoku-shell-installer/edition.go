package main

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"

	"ryoku-i18n"
	installerplan "ryoku-installerplan"
)

type editionCompositorPlan struct {
	edition string
	choices installerplan.EditionPlan
}

func compositorLabel(name string) string {
	if choice, ok := installerplan.ChoiceByID(installerplan.Compositor, name); ok {
		return choice.Label
	}
	return name
}

func editionPlanFromChoices(choices installerplan.EditionPlan) editionCompositorPlan {
	return editionCompositorPlan{
		edition: choices.Edition,
		choices: choices,
	}
}

func parseEditionCompositors(data []byte) (editionCompositorPlan, error) {
	choices, err := installerplan.ResolveEdition(data)
	if err != nil {
		return editionCompositorPlan{}, err
	}
	return editionPlanFromChoices(choices), nil
}

func sourceEditionChoices(name string) editionCompositorPlan {
	return editionPlanFromChoices(installerplan.ResolveSource(name))
}

func validateEditionChoice(kind, id string, plan editionCompositorPlan) error {
	availability, ok := plan.choices.Lookup(kind, id)
	if !ok {
		return nil
	}
	if availability.Available {
		return nil
	}
	return fmt.Errorf(i18n.T("%s choice %q is unavailable on %s: %s"),
		availability.Choice.Label, id, plan.edition, availability.Reason)
}

func validateEditionFlags(browser, shell string, plan editionCompositorPlan) error {
	if err := validateBrowser(browser); err != nil {
		return err
	}
	if err := validateEditionChoice(installerplan.Browser, browser, plan); err != nil {
		return err
	}
	if shell == "" {
		return nil
	}
	if err := validateLoginShell(shell); err != nil {
		return err
	}
	return validateEditionChoice(installerplan.LoginShell, shell, plan)
}

func loadEditionCompositors(client httpDoer, d *distro, ref, payload string) (editionCompositorPlan, error) {
	if d == nil {
		return sourceEditionChoices("Arch"), nil
	}
	if d.id != "fedora" && d.id != "void" {
		return sourceEditionChoices(d.name), nil
	}
	if payload != "" {
		path := filepath.Join(payload, d.id, "packages", "translations.tsv")
		data, err := os.ReadFile(path)
		if err != nil {
			return editionCompositorPlan{}, fmt.Errorf(i18n.T("read %s installer choices: %w"), d.name, err)
		}
		return parseEditionCompositors(data)
	}
	url := "https://raw.githubusercontent.com/ryoku-dev/ryoku/" + ref + "/" + d.id + "/packages/translations.tsv"
	resp, err := httpStatusOK(client, http.MethodGet, url)
	if err != nil {
		return editionCompositorPlan{}, fmt.Errorf(i18n.T("read %s installer choices from %s: %w"), d.name, url, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
	if err != nil {
		return editionCompositorPlan{}, err
	}
	return parseEditionCompositors(data)
}
