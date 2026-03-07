package main

import (
	"os/exec"
)

func notify(summary, body string) {
	exec.Command("notify-send",
		"--app-name=Habit Tracker",
		"--urgency=low",
		summary,
		body,
	).Run()
}
