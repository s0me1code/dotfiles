# Habit Tracker

Automatic time tracking for Hyprland. Watches which window is focused, matches it against task patterns, and records [org-mode CLOCK entries](https://orgmode.org/manual/Clocking-Work-Time.html) — all without Emacs.

## How It Works

```
Hyprland socket2 ──events──▶ habit-daemon.sh ──calls──▶ habit-clock.py ──writes──▶ Habits.org
                                    │
                                    ▼
                               notify-send
```

1. **habit-daemon.sh** connects to Hyprland's IPC socket (`.socket2.sock`) via `socat` and listens for window events.
2. When the focused window changes, it calls **habit-clock.py match** with the window title.
3. If the title matches a task's `HYPR_PATTERN` regex, it clocks in. If the task changes, it clocks out the old one first.
4. CLOCK entries are written directly into **Habits.org** inside each task's `:LOGBOOK:` drawer.
5. Desktop notifications are sent on clock-in/out via `notify-send`.

### State Reducer

The daemon keeps track of the last matched task. Repeated `activewindow` events for the same task are ignored — clock-in/out only fires when the matched task actually changes. This keeps CPU usage near zero during normal use.

### Events Handled

| Event | Action |
|---|---|
| `activewindow` | Match title against patterns, clock in/out as needed |
| `closewindow` | Query the new active window via `hyprctl`, re-evaluate |
| `lockscreen` | Clock out the current task |
| `unlockscreen` | Query active window, clock in if it matches |

## Files

```
~/.config/habits/
├── Habits.org              # Task definitions + CLOCK entries
├── habit-clock.py          # CLI for org-mode manipulation
├── habit-daemon.sh         # Hyprland event listener daemon
├── habit-sleep-hook        # Systemd sleep/wake hook (install to /usr/lib/systemd/system-sleep/)
├── state/                  # Runtime state (gitignored)
│   ├── active_task         # Current task name + timestamp
│   └── daemon.log          # Daemon log
└── archive/                # Old CLOCK entries moved here by `archive` command (gitignored)
    └── clock-YYYY.org

~/.config/systemd/user/
└── habit-watcher.service   # Systemd user service for the daemon
```

## Habits.org Format

Tasks live under a `* Tasks` heading. Each task has a `HYPR_PATTERN` property (regex matched against window titles) and a `:LOGBOOK:` drawer where CLOCK entries accumulate:

```org
#+TITLE: Habits & Task Tracker
#+STARTUP: overview

* Tasks
** Browser Research
   :PROPERTIES:
   :HYPR_PATTERN: Firefox|Brave|Chromium|Zen
   :DESCRIPTION: Web browsing and research
   :END:
   :LOGBOOK:
   CLOCK: [2026-03-07 Sat 10:30]--[2026-03-07 Sat 11:15] =>  0:45
   :END:
** Coding / Cursor
   :PROPERTIES:
   :HYPR_PATTERN: Cursor
   :DESCRIPTION: Coding in Cursor IDE
   :END:
   :LOGBOOK:
   :END:
```

To add a new task, add a `** Task Name` heading with a `:HYPR_PATTERN:` property. The pattern is a case-insensitive regex tested against the full window title.

## CLI Usage

```
habit-clock.py match   <window_title>   # Print matched task name (or empty)
habit-clock.py clockin <task name>      # Open a CLOCK entry, write state file
habit-clock.py clockout                 # Close the open CLOCK entry, delete state file
habit-clock.py status                   # Print "Task Name | H:MM" or "idle"
habit-clock.py today   [task name]      # Print today's totals
habit-clock.py archive                  # Move old entries to archive/clock-YYYY.org
```

### Examples

```bash
# What task matches this window?
python3 ~/.config/habits/habit-clock.py match "README.md — Cursor"
# → Coding / Cursor

# What am I working on right now?
python3 ~/.config/habits/habit-clock.py status
# → Coding / Cursor | 1:23

# How much time today?
python3 ~/.config/habits/habit-clock.py today
#   Browser Research: 0h 45m
#   Coding / Cursor: 2h 10m

# Move old entries out of Habits.org
python3 ~/.config/habits/habit-clock.py archive
# Archived 47 CLOCK entries to archive/ (years: 2026)
```

## Systemd Service

The daemon runs as a systemd user service that starts with the graphical session:

```ini
[Service]
ExecStart=%h/.config/habits/habit-daemon.sh
ExecStop=/usr/bin/python3 %h/.config/habits/habit-clock.py clockout
Restart=on-failure
PassEnvironment=HYPRLAND_INSTANCE_SIGNATURE XDG_RUNTIME_DIR DISPLAY WAYLAND_DISPLAY
```

```bash
# Enable and start
systemctl --user enable --now habit-watcher.service

# Check status
systemctl --user status habit-watcher

# View logs
journalctl --user -u habit-watcher -f
```

## Sleep/Wake Hook

A root-level hook at `/usr/lib/systemd/system-sleep/habit-sleep-hook` ensures:

- **Pre-suspend**: Clocks out the current task so sleep time is not counted.
- **Post-wake**: Restarts the daemon service so it reconnects to the (potentially new) Hyprland socket.

Install it manually:

```bash
sudo cp ~/.config/habits/habit-sleep-hook /usr/lib/systemd/system-sleep/
sudo chmod +x /usr/lib/systemd/system-sleep/habit-sleep-hook
```

## Quickshell Widget

A sidebar widget in the Quickshell desktop shell displays:

- **Current status**: Active task name and running duration, or "Idle".
- **Today's totals**: Per-task time breakdown for the current day.
- **Refresh button**: Manual refresh (auto-refreshes every 30s for status, 60s for totals).

The widget lives at `~/.config/quickshell/ii/modules/ii/sidebarLeft/HabitTracker.qml` and is included as a "Habits" tab in the left sidebar.

## Dotfiles Integration

Deployed via the end-4 dotfiles install system (`./setup install`). The entry in `sdata/subcmd-install/3.files-exp.yaml`:

```yaml
- from: "dots/.config/habits"
  to: "$XDG_CONFIG_HOME/habits"
  mode: "soft-backup"
  excludes: ["state"]
- from: "dots/.config/systemd/user/habit-watcher.service"
  to: "$XDG_CONFIG_HOME/systemd/user/habit-watcher.service"
  mode: "soft-backup"
```

The `state/` and `archive/` directories are gitignored since they contain runtime data.

## Dependencies

- **socat** — connects to Hyprland's Unix socket (`pacman -S socat`)
- **python3** — standard library only, no pip packages
- **hyprctl** — ships with Hyprland, used to query active window on `closewindow`/`unlockscreen`
- **notify-send** — desktop notifications (usually provided by `libnotify`)

## Planned: Go Rewrite

The system is being rewritten into a single Go binary (`habit-tracker`) using [hyprland-go](https://github.com/thiagokokada/hyprland-go) for native Hyprland IPC. This will:

- Eliminate the `socat` and `python3` dependencies.
- Replace three processes (bash + socat + python) with one ~5MB static binary.
- Remove per-event Python startup overhead (~30ms each).
- Handle socket connections natively via hyprland-go's `EventClient` and `RequestClient`.
