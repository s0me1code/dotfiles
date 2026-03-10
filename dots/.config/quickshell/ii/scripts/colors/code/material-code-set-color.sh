#!/usr/bin/env bash
COLOR_FILE_PATH="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/color.txt"
CURSOR_THEME_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/cursor"

# Define an array of possible VSCode settings file paths for various forks
settings_paths=(
    "${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"
    "${XDG_CONFIG_HOME:-$HOME/.config}/VSCodium/User/settings.json"
    "${XDG_CONFIG_HOME:-$HOME/.config}/Code - OSS/User/settings.json"
    "${XDG_CONFIG_HOME:-$HOME/.config}/Code - Insiders/User/settings.json"
    "${XDG_CONFIG_HOME:-$HOME/.config}/Cursor/User/settings.json"
    "${XDG_CONFIG_HOME:-$HOME/.config}/Antigravity/User/settings.json"
)

mode_flag="$1"
if [[ "$mode_flag" != "dark" && "$mode_flag" != "light" ]]; then
    current_mode="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'")"
    if [[ "$current_mode" == "prefer-dark" ]]; then
        mode_flag="dark"
    else
        mode_flag="light"
    fi
fi

if [[ ! -f "$COLOR_FILE_PATH" ]]; then
    exit 0
fi
new_color="$(cat "$COLOR_FILE_PATH")"

vscode_dark_theme="${VSCODE_THEME_DARK:-Material Code}"
vscode_light_theme="${VSCODE_THEME_LIGHT:-Material Code Light}"
cursor_dark_theme="${CURSOR_THEME_DARK:-Default Dark Modern}"
cursor_light_theme="${CURSOR_THEME_LIGHT:-Default Light Modern}"

if [[ "$mode_flag" == "dark" ]]; then
    generated_theme_json="$CURSOR_THEME_DIR/cursor-dark.json"
else
    generated_theme_json="$CURSOR_THEME_DIR/cursor-light.json"
fi

if ! command -v jq &>/dev/null; then
    exit 0
fi

# Loop through each settings file path
for CODE_SETTINGS_PATH in "${settings_paths[@]}"; do
    if [[ ! -f "$CODE_SETTINGS_PATH" ]]; then
        continue
    fi

    tmp_settings="$(mktemp)"
    # Cursor/VSCode settings files accept JSONC; normalize trailing commas for jq.
    normalized_json="$(python - "$CODE_SETTINGS_PATH" <<'PY'
import re
import sys
from pathlib import Path

settings_path = Path(sys.argv[1])
content = settings_path.read_text()
normalized = re.sub(r',\s*([}\]])', r'\1', content)
print(normalized, end="")
PY
)"

    if [[ "$CODE_SETTINGS_PATH" == *"/Cursor/User/settings.json" ]]; then
        if [[ "$mode_flag" == "dark" ]]; then
            theme_name="$cursor_dark_theme"
        else
            theme_name="$cursor_light_theme"
        fi
    else
        if [[ "$mode_flag" == "dark" ]]; then
            theme_name="$vscode_dark_theme"
        else
            theme_name="$vscode_light_theme"
        fi
    fi

    if [[ -f "$generated_theme_json" ]]; then
        if printf '%s\n' "$normalized_json" | jq \
            --arg new_color "$new_color" \
            --arg theme_name "$theme_name" \
            --slurpfile matugen_theme "$generated_theme_json" \
            '(. * ($matugen_theme[0] // {}))
            | .["material-code.primaryColor"] = $new_color
            | .["workbench.colorTheme"] = $theme_name' > "$tmp_settings"; then
            mv "$tmp_settings" "$CODE_SETTINGS_PATH"
        else
            rm -f "$tmp_settings"
        fi
    else
        if printf '%s\n' "$normalized_json" | jq \
            --arg new_color "$new_color" \
            --arg theme_name "$theme_name" \
            '.["material-code.primaryColor"] = $new_color
            | .["workbench.colorTheme"] = $theme_name' > "$tmp_settings"; then
            mv "$tmp_settings" "$CODE_SETTINGS_PATH"
        else
            rm -f "$tmp_settings"
        fi
    fi
done

