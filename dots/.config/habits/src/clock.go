package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"
)

func cmdMatch(title string) {
	lines, err := readOrg()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	tasks := parseTasks(lines)
	fmt.Println(matchTask(tasks, title))
}

func cmdClockIn(taskName string) {
	cmdClockOut()

	lines, err := readOrg()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	tasks := parseTasks(lines)

	var target *Task
	for i := range tasks {
		if tasks[i].Name == taskName {
			target = &tasks[i]
			break
		}
	}
	if target == nil {
		fmt.Fprintf(os.Stderr, "error: task '%s' not found in %s\n", taskName, orgFile)
		os.Exit(1)
	}

	now := time.Now()
	ts := orgTimestamp(now)

	lines = ensureLogbook(lines, target)

	clockLine := fmt.Sprintf("   CLOCK: %s\n", ts)
	insertPos := target.LogbookStart + 1

	newLines := make([]string, 0, len(lines)+1)
	newLines = append(newLines, lines[:insertPos]...)
	newLines = append(newLines, clockLine)
	newLines = append(newLines, lines[insertPos:]...)

	if err := writeOrg(newLines); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := writeState(taskName, ts); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func cmdClockOut() {
	taskName, tsStr, ok := readState()
	if !ok {
		return
	}

	now := time.Now()
	nowTs := orgTimestamp(now)

	startDt, err := parseOrgTimestamp(tsStr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "warning: could not parse timestamp '%s', removing stale state\n", tsStr)
		deleteState()
		return
	}
	_ = taskName

	diffMinutes := int(now.Sub(startDt).Minutes())
	duration := formatDuration(diffMinutes)

	lines, err := readOrg()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		deleteState()
		return
	}

	openPattern := "CLOCK: " + tsStr
	found := false
	for i, line := range lines {
		if strings.Contains(line, openPattern) && !strings.Contains(line, "--") {
			lines[i] = fmt.Sprintf("   CLOCK: %s--%s =>  %s\n", tsStr, nowTs, duration)
			found = true
			break
		}
	}

	if !found {
		fmt.Fprintf(os.Stderr, "warning: open CLOCK entry for '%s' not found in org file\n", tsStr)
	}

	if err := writeOrg(lines); err != nil {
		fmt.Fprintln(os.Stderr, err)
	}
	deleteState()
}

func cmdStatus() {
	taskName, tsStr, ok := readState()
	if !ok {
		fmt.Println("idle")
		return
	}

	startDt, err := parseOrgTimestamp(tsStr)
	if err != nil {
		fmt.Println("idle")
		return
	}

	diffMinutes := int(time.Since(startDt).Minutes())
	fmt.Printf("%s | %s\n", taskName, formatDuration(diffMinutes))
}

var closedRe = regexp.MustCompile(
	`CLOCK:\s*\[(\d{4}-\d{2}-\d{2})\s+\w+\s+(\d{2}:\d{2})\]--\[` +
		`(\d{4}-\d{2}-\d{2})\s+\w+\s+(\d{2}:\d{2})\]\s*=>\s*(\d+):(\d{2})`)

func cmdToday(filterTask string) {
	lines, err := readOrg()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	todayStr := time.Now().Format("2006-01-02")
	totals := make(map[string]int)
	var taskOrder []string

	currentTask := ""
	for _, line := range lines {
		stripped := strings.TrimSpace(line)
		if strings.HasPrefix(stripped, "** ") {
			currentTask = strings.TrimSpace(stripped[3:])
		} else if currentTask != "" && strings.Contains(line, "CLOCK:") && strings.Contains(line, "--") {
			m := closedRe.FindStringSubmatch(line)
			if m != nil && m[1] == todayStr {
				hours := atoi(m[5])
				mins := atoi(m[6])
				if _, exists := totals[currentTask]; !exists {
					taskOrder = append(taskOrder, currentTask)
				}
				totals[currentTask] += hours*60 + mins
			}
		}
	}

	if filterTask != "" {
		minutes := totals[filterTask]
		fmt.Printf("%s: %dh %02dm\n", filterTask, minutes/60, minutes%60)
	} else if len(totals) > 0 {
		for _, name := range taskOrder {
			minutes := totals[name]
			fmt.Printf("  %s: %dh %02dm\n", name, minutes/60, minutes%60)
		}
	} else {
		fmt.Println("  No entries today")
	}
}

var archiveRe = regexp.MustCompile(
	`CLOCK:\s*\[(\d{4})-(\d{2})-\d{2}\s+\w+\s+\d{2}:\d{2}\]--\[`)

func cmdArchive() {
	lines, err := readOrg()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	now := time.Now()
	currentYM := now.Format("2006-01")

	// year -> taskName -> []line
	archived := make(map[string]map[string][]string)
	linesToRemove := make(map[int]bool)

	currentTaskName := ""
	for i, line := range lines {
		stripped := strings.TrimSpace(line)
		if strings.HasPrefix(stripped, "** ") {
			currentTaskName = strings.TrimSpace(stripped[3:])
		} else if currentTaskName != "" && strings.Contains(line, "CLOCK:") && strings.Contains(line, "--") {
			m := archiveRe.FindStringSubmatch(line)
			if m != nil {
				entryYM := m[1] + "-" + m[2]
				if entryYM < currentYM {
					year := m[1]
					if archived[year] == nil {
						archived[year] = make(map[string][]string)
					}
					archived[year][currentTaskName] = append(archived[year][currentTaskName], line)
					linesToRemove[i] = true
				}
			}
		}
	}

	if len(linesToRemove) == 0 {
		fmt.Println("Nothing to archive (no entries older than this month)")
		return
	}

	if err := os.MkdirAll(archiveDir, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	years := make([]string, 0, len(archived))
	for y := range archived {
		years = append(years, y)
	}
	sort.Strings(years)

	for _, year := range years {
		taskEntries := archived[year]
		archiveFile := fmt.Sprintf("%s/clock-%s.org", archiveDir, year)

		existing := make(map[string][]string)
		var existingOrder []string
		if data, err := os.ReadFile(archiveFile); err == nil {
			currentHeading := ""
			for _, aline := range strings.SplitAfter(string(data), "\n") {
				astripped := strings.TrimSpace(aline)
				if strings.HasPrefix(astripped, "** ") {
					currentHeading = strings.TrimSpace(astripped[3:])
					if _, exists := existing[currentHeading]; !exists {
						existingOrder = append(existingOrder, currentHeading)
					}
					if existing[currentHeading] == nil {
						existing[currentHeading] = []string{}
					}
				} else if currentHeading != "" && strings.Contains(aline, "CLOCK:") {
					existing[currentHeading] = append(existing[currentHeading], aline)
				}
			}
		}

		for taskName, entries := range taskEntries {
			if _, exists := existing[taskName]; !exists {
				existingOrder = append(existingOrder, taskName)
			}
			existing[taskName] = append(existing[taskName], entries...)
		}

		sort.Strings(existingOrder)

		var buf strings.Builder
		fmt.Fprintf(&buf, "#+TITLE: Habit Clock Archive — %s\n\n", year)
		for _, taskName := range existingOrder {
			fmt.Fprintf(&buf, "** %s\n", taskName)
			buf.WriteString("   :LOGBOOK:\n")
			for _, entry := range existing[taskName] {
				if !strings.HasSuffix(entry, "\n") {
					entry += "\n"
				}
				buf.WriteString(entry)
			}
			buf.WriteString("   :END:\n")
		}

		if err := os.WriteFile(archiveFile, []byte(buf.String()), 0o644); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}

	newLines := make([]string, 0, len(lines))
	for i, line := range lines {
		if !linesToRemove[i] {
			newLines = append(newLines, line)
		}
	}
	if err := writeOrg(newLines); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	fmt.Printf("Archived %d CLOCK entries to %s/ (years: %s)\n",
		len(linesToRemove), archiveDir, strings.Join(years, ", "))
}

func atoi(s string) int {
	n := 0
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		}
	}
	return n
}
