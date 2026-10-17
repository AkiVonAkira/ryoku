package updater

import "testing"

func TestUpdateAnswersHelpInsteadOfUpdating(t *testing.T) {
	for _, flag := range []string{"-h", "--help"} {
		help, unknown := readUpdateOptions([]string{flag})
		if !help {
			t.Errorf("%s did not ask for help, so the run would have updated the machine", flag)
		}
		if unknown != "" {
			t.Errorf("%s was also read as an unknown option %q", flag, unknown)
		}
	}
	if help, _ := readUpdateOptions([]string{"--system", "--help"}); !help {
		t.Error("help behind another option was missed")
	}
}

func TestAnOptionUpdateDoesNotKnowIsRefused(t *testing.T) {
	// The whole point: this used to be ignored, and the machine was updated.
	for _, flag := range []string{"--dry-run", "--sytem", "--n"} {
		help, unknown := readUpdateOptions([]string{flag})
		if help {
			t.Errorf("%s was read as a request for help", flag)
		}
		if unknown != flag {
			t.Errorf("%s was not refused; got %q", flag, unknown)
		}
	}
}

func TestEveryOptionUpdateActsOnIsAccepted(t *testing.T) {
	known := []string{"-v", "--verbose", "--channel-switch", "--system", "--full", "--wait", "--force", "--unchecked", "--gui", "--gui-host", "--auth", "--cancel"}
	if help, unknown := readUpdateOptions(known); help || unknown != "" {
		t.Errorf("a run with every valid option was turned away: help=%v unknown=%q", help, unknown)
	}
}

func TestTheValueAfterStage2IsNotMistakenForAnOption(t *testing.T) {
	if _, unknown := readUpdateOptions([]string{"--stage2", "--whatever-the-run-hands-itself"}); unknown != "" {
		t.Errorf("the stage2 value was refused as an option: %q", unknown)
	}
}
