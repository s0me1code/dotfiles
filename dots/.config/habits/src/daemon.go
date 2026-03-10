package main

import (
	"bufio"
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"
	"time"

	hyprland "github.com/thiagokokada/hyprland-go"
	"github.com/thiagokokada/hyprland-go/event"
	"github.com/thiagokokada/hyprland-go/helpers"
)

var logFile *os.File

func daemonLog(msg string) {
	ts := time.Now().Format("2006-01-02 15:04:05")
	line := fmt.Sprintf("[%s] %s\n", ts, msg)
	if logFile != nil {
		logFile.WriteString(line)
	}
}

type habitHandler struct {
	event.DefaultEventHandler
	reqClient *hyprland.RequestClient
	mu        sync.Mutex
	lastTask  string
	lastTitle string
}

func (h *habitHandler) evaluateTitle(title string) {
	h.mu.Lock()
	defer h.mu.Unlock()

	lines, err := readOrg()
	if err != nil {
		return
	}
	tasks := parseTasks(lines)
	matched := matchTask(tasks, title)

	if matched == h.lastTask {
		return
	}

	if h.lastTask != "" {
		cmdClockOut()
		daemonLog("clockout: " + h.lastTask)
		notify("⏹ Clocked Out", h.lastTask+"\n(switched away)")
	}

	if matched != "" {
		cmdClockIn(matched)
		daemonLog(fmt.Sprintf("clockin: %s (title: %s)", matched, title))
		notify("⏱ Clocking In", matched)
	}

	h.lastTask = matched
	if title != "" {
		h.lastTitle = title
	}
}

func (h *habitHandler) ActiveWindow(w event.ActiveWindow) {
	h.evaluateTitle(w.Title)
}

func (h *habitHandler) CloseWindow(_ event.CloseWindow) {
	time.Sleep(200 * time.Millisecond)
	win, err := h.reqClient.ActiveWindow()
	if err != nil {
		return
	}
	h.evaluateTitle(win.Title)
}

func (h *habitHandler) handleLock() {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.lastTask != "" {
		cmdClockOut()
		daemonLog("clockout (lock): " + h.lastTask)
		notify("⏹ Clocked Out", h.lastTask+"\n(screen locked)")
	}
	h.lastTask = ""
	h.lastTitle = ""
}

func (h *habitHandler) handleUnlock() {
	time.Sleep(1 * time.Second)
	win, err := h.reqClient.ActiveWindow()
	if err != nil {
		return
	}
	h.evaluateTitle(win.Title)
}

// lockWatcher reads raw socket2 events for lockscreen/unlockscreen,
// which hyprland-go does not yet support as typed events.
func lockWatcher(ctx context.Context, handler *habitHandler) {
	socketPath, err := helpers.GetSocket(helpers.EventSocket)
	if err != nil {
		daemonLog("lock watcher: cannot get socket path: " + err.Error())
		return
	}

	conn, err := net.Dial("unix", socketPath)
	if err != nil {
		daemonLog("lock watcher: cannot connect: " + err.Error())
		return
	}

	go func() {
		<-ctx.Done()
		conn.Close()
	}()

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		line := scanner.Text()
		parts := strings.SplitN(line, ">>", 2)
		if len(parts) < 2 {
			continue
		}
		switch parts[0] {
		case "lockscreen":
			handler.handleLock()
		case "unlockscreen":
			handler.handleUnlock()
		}
	}
}

func cmdDaemon() {
	if err := os.MkdirAll(stateDir, 0o755); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	var err error
	logPath := stateDir + "/daemon.log"
	logFile, err = os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error opening log: %v\n", err)
		os.Exit(1)
	}
	defer logFile.Close()

	daemonLog("daemon starting")

	if _, serr := os.Stat(stateFile); serr == nil {
		daemonLog("found stale state file from previous run, clocking out")
		cmdClockOut()
	}

	ctx, cancel := context.WithCancel(context.Background())

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT, syscall.SIGHUP)
	go func() {
		sig := <-sigCh
		daemonLog(fmt.Sprintf("received signal: %v", sig))
		cancel()
	}()

	reqClient := hyprland.MustClient()
	evClient := event.MustClient()
	defer evClient.Close()

	handler := &habitHandler{
		reqClient: reqClient,
	}

	if win, err := reqClient.ActiveWindow(); err == nil && win.Title != "" {
		handler.evaluateTitle(win.Title)
	}

	daemonLog("connected to Hyprland sockets, listening for events")

	go lockWatcher(ctx, handler)

	err = evClient.Subscribe(
		ctx,
		handler,
		event.EventActiveWindow,
		event.EventCloseWindow,
	)

	if err != nil && ctx.Err() == nil {
		daemonLog("event subscription error: " + err.Error())
		fmt.Fprintln(os.Stderr, "event subscription error:", err)
	}

	handler.mu.Lock()
	if handler.lastTask != "" {
		daemonLog("daemon stopping, running clockout")
		cmdClockOut()
	} else {
		daemonLog("daemon stopping (idle)")
	}
	handler.mu.Unlock()

	daemonLog("daemon stopped")
}
