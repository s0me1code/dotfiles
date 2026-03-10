# Habit Tracker

Automatic time tracking for Hyprland. Watches which window is focused, matches it against task patterns, and records [org-mode CLOCK entries](https://orgmode.org/manual/Clocking-Work-Time.html) -- all without Emacs.

## How It Works

```
Hyprland socket2 ──events──> habit-tracker daemon ──writes──> Habits.org
       |                            |
Hyprland socket  <──queries─────────┘
       |                            |
       └────────────────────────────└──> notify-send
```

A single Go binary (`habit-tracker`) handles everything:

1. The **daemon** subcommand connects to Hyprland's IPC sockets using [hyprland-go](https://github.com/thiagokokada/hyprland-go) and listens for window events.
2. When the focused window changes, it matches the title against task `HYPR_PATTERN` regexes.
3. If the task changes, it clocks out the old one and clocks in the new one.
4. CLOCK entries are written directly into **Habits.org** inside each task's `:LOGBOOK:` drawer.
5. Desktop notifications are sent on clock-in/out via `notify-send`.

### State Reducer

The daemon keeps track of the last matched task. Repeated `activewindow` events for the same task are ignored -- clock-in/out only fires when the matched task actually changes. This keeps CPU usage near zero during normal use.

### Events Handled

| Event | Action |
|---|---|
| `activewindow` | Match title against patterns, clock in/out as needed |
| `closewindow` | Query the new active window via hyprland-go `RequestClient`, re-evaluate |
| `lockscreen` | Clock out the current task |
| `unlockscreen` | Query active window, clock in if it matches |

### hyprland-go Integration

The daemon uses [hyprland-go](https://github.com/thiagokokada/hyprland-go) v0.4.1 following the library's patterns:

- `event.MustClient()` + `event.DefaultEventHandler` embedding for typed event handling
- `hyprland.MustClient()` + `c.ActiveWindow()` for querying the focused window (replaces `hyprctl` subprocess calls)
- `c.Subscribe(ctx, handler, ...)` as the main blocking event loop
- `context.WithCancel` + `signal.Notify` for clean SIGTERM/SIGINT/SIGHUP shutdown

Lock/unlock events (not yet in hyprland-go's typed event set) are handled by a lightweight goroutine reading raw socket2 lines.

## Files

```
~/.config/habits/
├── Habits.org              # Task definitions + CLOCK entries
├── habit-tracker           # Go binary (all CLI + daemon)
├── habit-sleep-hook        # Systemd sleep/wake hook (install to /usr/lib/systemd/system-sleep/)
├── src/                    # Go source code
│   ├── go.mod
│   ├── go.sum
│   ├── main.go             # CLI dispatch
│   ├── org.go              # Org file parsing, atomic writes
│   ├── clock.go            # clockin/clockout/status/today/archive
│   ├── daemon.go           # hyprland-go event handler + lock watcher
│   └── notify.go           # notify-send wrapper
├── state/                  # Runtime state (gitignored)
│   ├── active_task         # Current task name + timestamp
│   └── daemon.log          # Daemon log
└── archive/                # Old CLOCK entries (gitignored)
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
habit-tracker match   <window_title>   # Print matched task name (or empty)
habit-tracker clockin <task name>      # Open a CLOCK entry, write state file
habit-tracker clockout                 # Close the open CLOCK entry, delete state file
habit-tracker status                   # Print "Task Name | H:MM" or "idle"
habit-tracker today   [task name]      # Print today's totals
habit-tracker archive                  # Move old entries to archive/clock-YYYY.org
habit-tracker daemon                   # Run the Hyprland event listener
```

### Examples

```bash
# What task matches this window?
~/.config/habits/habit-tracker match "README.md — Cursor"
# → Coding / Cursor

# What am I working on right now?
~/.config/habits/habit-tracker status
# → Coding / Cursor | 1:23

# How much time today?
~/.config/habits/habit-tracker today
#   Browser Research: 0h 45m
#   Coding / Cursor: 2h 10m

# Move old entries out of Habits.org
~/.config/habits/habit-tracker archive
# Archived 47 CLOCK entries to archive/ (years: 2026)
```

## Building from Source

```bash
cd ~/.config/habits/src
go build -o ../habit-tracker .
```

Requires Go 1.21+. Single dependency: `github.com/thiagokokada/hyprland-go v0.4.1`.

## Systemd Service

The daemon runs as a systemd user service that starts with the graphical session:

```ini
[Service]
ExecStart=%h/.config/habits/habit-tracker daemon
ExecStop=%h/.config/habits/habit-tracker clockout
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

The `state/`, `archive/`, and `habit-tracker` binary are gitignored.

## Resource Usage

Measured via systemd:

- **Memory**: ~5-6 MB (single Go binary, no child processes)
- **CPU**: 14ms total at startup, near-zero idle
- **Disk**: One small org file write per window switch

Compared to the previous Python+bash implementation (bash + socat + python3 spawns per event), this is a single process with no subprocess overhead.
