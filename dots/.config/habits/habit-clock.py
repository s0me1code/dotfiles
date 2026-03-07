#!/usr/bin/env python3
"""Habit clock-in/out CLI for org-mode CLOCK entries.

Subcommands:
    match   <window_title>   Print matched task name or empty string
    clockin <task name>      Insert open CLOCK entry, write state file
    clockout                 Close open CLOCK entry, delete state file
    status                   Print "Task Name | H:MM" or "idle"
    today   [task name]      Print today's totals from closed CLOCK entries
    archive                  Move old CLOCK entries to yearly archive files
"""

import os
import re
import sys
import tempfile
from datetime import datetime
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("HABIT_CONFIG_DIR", Path.home() / ".config" / "habits"))
ORG_FILE = CONFIG_DIR / "Habits.org"
STATE_DIR = CONFIG_DIR / "state"
STATE_FILE = STATE_DIR / "active_task"
ARCHIVE_DIR = CONFIG_DIR / "archive"


def org_timestamp(dt: datetime) -> str:
    return dt.strftime("[%Y-%m-%d %a %H:%M]")


def parse_org_timestamp(s: str) -> datetime:
    s = s.strip().strip("[]")
    return datetime.strptime(s, "%Y-%m-%d %a %H:%M")


def format_duration(minutes: int) -> str:
    h, m = divmod(abs(minutes), 60)
    return f"{h}:{m:02d}"


def read_org() -> list[str]:
    return ORG_FILE.read_text().splitlines(keepends=True)


def write_org(lines: list[str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CONFIG_DIR, suffix=".org.tmp")
    try:
        with os.fdopen(fd, "w") as f:
            f.writelines(lines)
        os.replace(tmp, ORG_FILE)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def parse_tasks(lines: list[str]) -> list[dict]:
    """Parse ** headings with their :PROPERTIES: and :LOGBOOK: drawer line indices."""
    tasks = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("** "):
            name = line[3:].strip()
            task = {"name": name, "line": i, "pattern": None, "logbook_start": None, "logbook_end": None}

            j = i + 1
            in_properties = False
            in_logbook = False
            while j < len(lines):
                sl = lines[j].strip()
                if sl.startswith("** ") or sl.startswith("* "):
                    break
                if sl == ":PROPERTIES:":
                    in_properties = True
                elif in_properties and sl == ":END:":
                    in_properties = False
                elif in_properties and sl.startswith(":HYPR_PATTERN:"):
                    task["pattern"] = sl.split(":HYPR_PATTERN:", 1)[1].strip()
                elif sl == ":LOGBOOK:":
                    in_logbook = True
                    task["logbook_start"] = j
                elif in_logbook and sl == ":END:":
                    task["logbook_end"] = j
                    in_logbook = False
                j += 1

            tasks.append(task)
        i += 1
    return tasks


def cmd_match(title: str) -> None:
    lines = read_org()
    tasks = parse_tasks(lines)
    for task in tasks:
        if task["pattern"] and re.search(task["pattern"], title, re.IGNORECASE):
            print(task["name"])
            return
    print("")


def read_state() -> tuple[str, str] | None:
    try:
        content = STATE_FILE.read_text().strip()
        if not content:
            return None
        parts = content.split("\n", 1)
        if len(parts) != 2:
            print(f"warning: corrupted state file, ignoring", file=sys.stderr)
            return None
        return parts[0].strip(), parts[1].strip()
    except FileNotFoundError:
        return None


def write_state(task_name: str, timestamp: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(f"{task_name}\n{timestamp}\n")


def delete_state() -> None:
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass


def ensure_logbook(lines: list[str], task: dict) -> tuple[list[str], dict]:
    """If the task has no :LOGBOOK: drawer, create one after :PROPERTIES:....:END:."""
    if task["logbook_start"] is not None:
        return lines, task

    insert_at = task["line"] + 1
    j = insert_at
    in_properties = False
    while j < len(lines):
        sl = lines[j].strip()
        if sl.startswith("** ") or sl.startswith("* "):
            break
        if sl == ":PROPERTIES:":
            in_properties = True
        elif in_properties and sl == ":END:":
            insert_at = j + 1
            break
        j += 1

    logbook_lines = ["   :LOGBOOK:\n", "   :END:\n"]
    lines = lines[:insert_at] + logbook_lines + lines[insert_at:]
    task["logbook_start"] = insert_at
    task["logbook_end"] = insert_at + 1
    return lines, task


def cmd_clockin(task_name: str) -> None:
    cmd_clockout()

    lines = read_org()
    tasks = parse_tasks(lines)

    target = None
    for t in tasks:
        if t["name"] == task_name:
            target = t
            break

    if target is None:
        print(f"error: task '{task_name}' not found in {ORG_FILE}", file=sys.stderr)
        sys.exit(1)

    now = datetime.now()
    ts = org_timestamp(now)

    lines, target = ensure_logbook(lines, target)

    clock_line = f"   CLOCK: {ts}\n"
    insert_pos = target["logbook_start"] + 1
    lines.insert(insert_pos, clock_line)

    write_org(lines)
    write_state(task_name, ts)


def cmd_clockout() -> None:
    state = read_state()
    if state is None:
        return

    task_name, ts_str = state
    now = datetime.now()
    now_ts = org_timestamp(now)

    try:
        start_dt = parse_org_timestamp(ts_str)
    except ValueError:
        print(f"warning: could not parse timestamp '{ts_str}', removing stale state", file=sys.stderr)
        delete_state()
        return

    diff_minutes = int((now - start_dt).total_seconds() / 60)
    duration = format_duration(diff_minutes)

    lines = read_org()
    open_pattern = f"CLOCK: {ts_str}"
    found = False
    for i, line in enumerate(lines):
        if open_pattern in line and "--" not in line:
            closed = f"   CLOCK: {ts_str}--{now_ts} =>  {duration}\n"
            lines[i] = closed
            found = True
            break

    if not found:
        print(f"warning: open CLOCK entry for '{ts_str}' not found in org file", file=sys.stderr)

    write_org(lines)
    delete_state()


def cmd_status() -> None:
    state = read_state()
    if state is None:
        print("idle")
        return

    task_name, ts_str = state
    try:
        start_dt = parse_org_timestamp(ts_str)
    except ValueError:
        print("idle")
        return

    diff_minutes = int((datetime.now() - start_dt).total_seconds() / 60)
    print(f"{task_name} | {format_duration(diff_minutes)}")


def cmd_today(filter_task: str | None = None) -> None:
    lines = read_org()
    tasks = parse_tasks(lines)
    today_str = datetime.now().strftime("%Y-%m-%d")

    closed_re = re.compile(
        r"CLOCK:\s*\[(\d{4}-\d{2}-\d{2})\s+\w+\s+(\d{2}:\d{2})\]--\["
        r"(\d{4}-\d{2}-\d{2})\s+\w+\s+(\d{2}:\d{2})\]\s*=>\s*(\d+):(\d{2})"
    )

    totals: dict[str, int] = {}

    current_task = None
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("** "):
            current_task = stripped[3:].strip()
        elif current_task and "CLOCK:" in line and "--" in line:
            m = closed_re.search(line)
            if m and m.group(1) == today_str:
                hours, mins = int(m.group(5)), int(m.group(6))
                totals[current_task] = totals.get(current_task, 0) + hours * 60 + mins

    if filter_task:
        minutes = totals.get(filter_task, 0)
        h, m = divmod(minutes, 60)
        print(f"{filter_task}: {h}h {m:02d}m")
    elif totals:
        for name, minutes in totals.items():
            h, m = divmod(minutes, 60)
            print(f"  {name}: {h}h {m:02d}m")
    else:
        print("  No entries today")


def cmd_archive() -> None:
    """Move CLOCK entries older than the current month to yearly archive files."""
    lines = read_org()
    tasks = parse_tasks(lines)
    now = datetime.now()
    current_ym = now.strftime("%Y-%m")

    closed_re = re.compile(
        r"CLOCK:\s*\[(\d{4})-(\d{2})-\d{2}\s+\w+\s+\d{2}:\d{2}\]--\["
    )

    archived: dict[str, dict[str, list[str]]] = {}
    lines_to_remove: set[int] = set()

    current_task_name = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("** "):
            current_task_name = stripped[3:].strip()
        elif current_task_name and "CLOCK:" in line and "--" in line:
            m = closed_re.search(line)
            if m:
                entry_ym = f"{m.group(1)}-{m.group(2)}"
                if entry_ym < current_ym:
                    year = m.group(1)
                    archived.setdefault(year, {}).setdefault(current_task_name, []).append(line)
                    lines_to_remove.add(i)

    if not lines_to_remove:
        print("Nothing to archive (no entries older than this month)")
        return

    ARCHIVE_DIR.mkdir(parents=True, exist_ok=True)

    for year, task_entries in sorted(archived.items()):
        archive_file = ARCHIVE_DIR / f"clock-{year}.org"
        existing: dict[str, list[str]] = {}
        if archive_file.exists():
            current_heading = None
            for aline in archive_file.read_text().splitlines(keepends=True):
                astripped = aline.strip()
                if astripped.startswith("** "):
                    current_heading = astripped[3:].strip()
                    existing.setdefault(current_heading, [])
                elif current_heading and "CLOCK:" in aline:
                    existing[current_heading].append(aline)

        for task_name, entries in task_entries.items():
            existing.setdefault(task_name, []).extend(entries)

        with open(archive_file, "w") as f:
            f.write(f"#+TITLE: Habit Clock Archive — {year}\n\n")
            for task_name in sorted(existing.keys()):
                f.write(f"** {task_name}\n")
                f.write("   :LOGBOOK:\n")
                for entry in existing[task_name]:
                    if not entry.endswith("\n"):
                        entry += "\n"
                    f.write(entry)
                f.write("   :END:\n")

    new_lines = [line for i, line in enumerate(lines) if i not in lines_to_remove]
    write_org(new_lines)

    total_moved = len(lines_to_remove)
    years_affected = ", ".join(sorted(archived.keys()))
    print(f"Archived {total_moved} CLOCK entries to {ARCHIVE_DIR}/ (years: {years_affected})")


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "match":
        if len(sys.argv) < 3:
            print("usage: habit-clock.py match <window_title>", file=sys.stderr)
            sys.exit(1)
        cmd_match(sys.argv[2])
    elif cmd == "clockin":
        if len(sys.argv) < 3:
            print("usage: habit-clock.py clockin <task name>", file=sys.stderr)
            sys.exit(1)
        cmd_clockin(sys.argv[2])
    elif cmd == "clockout":
        cmd_clockout()
    elif cmd == "status":
        cmd_status()
    elif cmd == "today":
        filter_task = sys.argv[2] if len(sys.argv) >= 3 else None
        cmd_today(filter_task)
    elif cmd == "archive":
        cmd_archive()
    else:
        print(f"unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
