package main

import (
	"fmt"
	"os"
)

const usage = `Habit clock-in/out CLI for org-mode CLOCK entries.

Subcommands:
    match   <window_title>   Print matched task name or empty string
    clockin <task name>      Insert open CLOCK entry, write state file
    clockout                 Close open CLOCK entry, delete state file
    status                   Print "Task Name | H:MM" or "idle"
    today   [task name]      Print today's totals from closed CLOCK entries
    archive                  Move old CLOCK entries to yearly archive files
    daemon                   Run Hyprland event listener (replaces habit-daemon.sh)
`

func main() {
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(1)
	}

	switch os.Args[1] {
	case "match":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: habit-tracker match <window_title>")
			os.Exit(1)
		}
		cmdMatch(os.Args[2])
	case "clockin":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: habit-tracker clockin <task name>")
			os.Exit(1)
		}
		cmdClockIn(os.Args[2])
	case "clockout":
		cmdClockOut()
	case "status":
		cmdStatus()
	case "today":
		filterTask := ""
		if len(os.Args) >= 3 {
			filterTask = os.Args[2]
		}
		cmdToday(filterTask)
	case "archive":
		cmdArchive()
	case "daemon":
		cmdDaemon()
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}
