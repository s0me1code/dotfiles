# Tmux Configuration

## Prerequisites

- [tmux](https://github.com/tmux/tmux) (>= 3.0)
- [fish shell](https://fishshell.com/) (configured as default shell)
- [fzf](https://github.com/junegunn/fzf) (required by tmux-fzf and tmux-fzf-url)

## Installing Plugins

This config uses [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm) to manage plugins.

### 1. Install TPM

```bash
git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm
```

### 2. Install plugins

**Option A** — From inside tmux, press `prefix` + <kbd>I</kbd> (capital i) to fetch and install all plugins listed in `tmux.conf`.

**Option B** — From the command line (no tmux session required):

```bash
tmux start-server \; source-file ~/.config/tmux/tmux.conf
~/.config/tmux/plugins/tpm/bin/install_plugins
```

### 3. Reload tmux config

Inside tmux, press `prefix` + <kbd>r</kbd> to reload, or run:

```bash
tmux source-file ~/.config/tmux/tmux.conf
```

## Updating Plugins

Inside tmux, press `prefix` + <kbd>U</kbd> (capital u) to update all plugins.

## Removing Plugins

1. Remove or comment out the `set -g @plugin '...'` line in `tmux.conf`.
2. Inside tmux, press `prefix` + <kbd>alt</kbd> + <kbd>u</kbd> to remove plugins no longer in the config.

## Installed Plugins

| Plugin | Description |
|--------|-------------|
| [tpm](https://github.com/tmux-plugins/tpm) | Tmux Plugin Manager |
| [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect) | Save and restore tmux sessions |
| [tmux-sensible](https://github.com/tmux-plugins/tmux-sensible) | Sensible default settings |
| [tmux-yank](https://github.com/tmux-plugins/tmux-yank) | Copy to system clipboard |
| [tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) | Continuous session saving/restoring |
| [tmux-thumbs](https://github.com/fcsonline/tmux-thumbs) | Quick text selection with hints |
| [tmux-fzf](https://github.com/sainnhe/tmux-fzf) | Fuzzy finder integration |
| [tmux-fzf-url](https://github.com/wfxr/tmux-fzf-url) | Open URLs with fzf |
| [tmux-sessionx](https://github.com/omerxx/tmux-sessionx) | Enhanced session management |
| [tmux-floax](https://github.com/omerxx/tmux-floax) | Floating window support |

## Key Bindings

The prefix key is `Ctrl-A`.

| Binding | Action |
|---------|--------|
| `prefix` + `\|` | Split pane horizontally |
| `prefix` + `-` | Split pane vertically |
| `prefix` + `r` | Reload config |
| `prefix` + <kbd>I</kbd> | Install plugins |
| `prefix` + <kbd>U</kbd> | Update plugins |
| `Alt` + `←/→/↑/↓` | Navigate panes |
| `Alt` + `Space` | Next window |
| `Alt` + `0-9` | Switch to window N |
