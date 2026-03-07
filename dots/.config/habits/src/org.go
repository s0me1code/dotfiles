package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

var configDir string
var orgFile string
var stateDir string
var stateFile string
var archiveDir string

func init() {
	configDir = os.Getenv("HABIT_CONFIG_DIR")
	if configDir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			fmt.Fprintln(os.Stderr, "error: cannot determine home directory")
			os.Exit(1)
		}
		configDir = filepath.Join(home, ".config", "habits")
	}
	orgFile = filepath.Join(configDir, "Habits.org")
	stateDir = filepath.Join(configDir, "state")
	stateFile = filepath.Join(stateDir, "active_task")
	archiveDir = filepath.Join(configDir, "archive")
}

type Task struct {
	Name         string
	Line         int
	Pattern      string
	LogbookStart int // -1 if absent
	LogbookEnd   int // -1 if absent
}

func orgTimestamp(t time.Time) string {
	weekday := t.Weekday().String()[:3]
	return fmt.Sprintf("[%04d-%02d-%02d %s %02d:%02d]",
		t.Year(), t.Month(), t.Day(), weekday, t.Hour(), t.Minute())
}

func parseOrgTimestamp(s string) (time.Time, error) {
	s = strings.TrimSpace(s)
	s = strings.Trim(s, "[]")
	return time.ParseInLocation("2006-01-02 Mon 15:04", s, time.Local)
}

func formatDuration(minutes int) string {
	if minutes < 0 {
		minutes = -minutes
	}
	return fmt.Sprintf("%d:%02d", minutes/60, minutes%60)
}

func readOrg() ([]string, error) {
	data, err := os.ReadFile(orgFile)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", orgFile, err)
	}
	content := string(data)
	if content == "" {
		return []string{}, nil
	}
	lines := strings.SplitAfter(content, "\n")
	if lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	return lines, nil
}

func writeOrg(lines []string) error {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(configDir, "*.org.tmp")
	if err != nil {
		return err
	}
	tmpName := tmp.Name()

	_, writeErr := tmp.WriteString(strings.Join(lines, ""))
	closeErr := tmp.Close()
	if writeErr != nil {
		os.Remove(tmpName)
		return writeErr
	}
	if closeErr != nil {
		os.Remove(tmpName)
		return closeErr
	}
	if err := os.Rename(tmpName, orgFile); err != nil {
		os.Remove(tmpName)
		return err
	}
	return nil
}

func parseTasks(lines []string) []Task {
	var tasks []Task
	i := 0
	for i < len(lines) {
		line := lines[i]
		if strings.HasPrefix(line, "** ") {
			name := strings.TrimSpace(line[3:])
			task := Task{
				Name:         name,
				Line:         i,
				LogbookStart: -1,
				LogbookEnd:   -1,
			}

			j := i + 1
			inProperties := false
			inLogbook := false
			for j < len(lines) {
				sl := strings.TrimSpace(lines[j])
				if strings.HasPrefix(sl, "** ") || strings.HasPrefix(sl, "* ") {
					break
				}
				if sl == ":PROPERTIES:" {
					inProperties = true
				} else if inProperties && sl == ":END:" {
					inProperties = false
				} else if inProperties && strings.HasPrefix(sl, ":HYPR_PATTERN:") {
					task.Pattern = strings.TrimSpace(strings.SplitN(sl, ":HYPR_PATTERN:", 2)[1])
				} else if sl == ":LOGBOOK:" {
					inLogbook = true
					task.LogbookStart = j
				} else if inLogbook && sl == ":END:" {
					task.LogbookEnd = j
					inLogbook = false
				}
				j++
			}
			tasks = append(tasks, task)
		}
		i++
	}
	return tasks
}

func matchTask(tasks []Task, title string) string {
	for _, t := range tasks {
		if t.Pattern == "" {
			continue
		}
		re, err := regexp.Compile("(?i)" + t.Pattern)
		if err != nil {
			continue
		}
		if re.MatchString(title) {
			return t.Name
		}
	}
	return ""
}

func readState() (taskName, timestamp string, ok bool) {
	data, err := os.ReadFile(stateFile)
	if err != nil {
		return "", "", false
	}
	content := strings.TrimSpace(string(data))
	if content == "" {
		return "", "", false
	}
	parts := strings.SplitN(content, "\n", 2)
	if len(parts) != 2 {
		fmt.Fprintln(os.Stderr, "warning: corrupted state file, ignoring")
		return "", "", false
	}
	return strings.TrimSpace(parts[0]), strings.TrimSpace(parts[1]), true
}

func writeState(taskName, timestamp string) error {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		return err
	}
	return os.WriteFile(stateFile, []byte(taskName+"\n"+timestamp+"\n"), 0o644)
}

func deleteState() {
	os.Remove(stateFile)
}

func ensureLogbook(lines []string, task *Task) []string {
	if task.LogbookStart >= 0 {
		return lines
	}

	insertAt := task.Line + 1
	j := insertAt
	inProperties := false
	for j < len(lines) {
		sl := strings.TrimSpace(lines[j])
		if strings.HasPrefix(sl, "** ") || strings.HasPrefix(sl, "* ") {
			break
		}
		if sl == ":PROPERTIES:" {
			inProperties = true
		} else if inProperties && sl == ":END:" {
			insertAt = j + 1
			break
		}
		j++
	}

	logbookLines := []string{"   :LOGBOOK:\n", "   :END:\n"}
	newLines := make([]string, 0, len(lines)+2)
	newLines = append(newLines, lines[:insertAt]...)
	newLines = append(newLines, logbookLines...)
	newLines = append(newLines, lines[insertAt:]...)

	task.LogbookStart = insertAt
	task.LogbookEnd = insertAt + 1
	return newLines
}
