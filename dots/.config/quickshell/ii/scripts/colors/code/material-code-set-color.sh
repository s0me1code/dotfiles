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
    "${XDG_CONFIG_HOME:-$HOME/.config}/Windsurf/User/settings.json"
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
cursor_dark_theme="${CURSOR_THEME_DARK:-Material Code}"
cursor_light_theme="${CURSOR_THEME_LIGHT:-Material Code Light}"

if [[ "$mode_flag" == "dark" ]]; then
    generated_theme_json="$CURSOR_THEME_DIR/cursor-dark.json"
else
    generated_theme_json="$CURSOR_THEME_DIR/cursor-light.json"
fi

_config_type=$(jq -r '.appearance.palette.type // "scheme-tonal-spot"' "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse/config.json" 2>/dev/null)
[[ "$_config_type" == "auto" || -z "$_config_type" || "$_config_type" == "null" ]] && _config_type="scheme-tonal-spot"
# Regenerate cursor theme JSON using hex color + correct scheme type (works without a TTY,
# unlike image mode which fails when launched from QuickShell).
if command -v matugen &>/dev/null; then
    matugen color hex "$new_color" --mode "$mode_flag" --type "$_config_type"
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
content = settings_path.read_text() or "{}"
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
            --arg mode_flag "$mode_flag" \
            --slurpfile matugen_theme "$generated_theme_json" \
            '(. * ($matugen_theme[0] // {}))
            | .["material-code.primaryColor"] = $new_color
            | .["workbench.colorTheme"] = $theme_name
            | .["material-code.colors"] = (
                (.["material-code.colors"] // {})
                | {
                    foreground,
                    mutedForeground,
                    background,
                    card,
                    popover,
                    hover,
                    border,
                    primary,
                    primaryForeground,
                    secondary,
                    secondaryForeground,
                    error,
                    errorForeground,
                    success,
                    warning
                }
              )
            | .["indentRainbow.colors"] = (
                if ((($matugen_theme[0] // {})["indentRainbow.colors"] | type) == "array")
                    and (((($matugen_theme[0] // {})["indentRainbow.colors"]) | length) > 0) then
                    (($matugen_theme[0] // {})["indentRainbow.colors"])
                else
                    (if $mode_flag == "dark" then
                        [
                            ((.["material-code.colors"].primary // $new_color) + "28"),
                            ((.["material-code.colors"].primary // $new_color) + "3c"),
                            ((.["material-code.colors"].primary // $new_color) + "50"),
                            ((.["material-code.colors"].primary // $new_color) + "64"),
                            ((.["material-code.colors"].primary // $new_color) + "78"),
                            ((.["material-code.colors"].primary // $new_color) + "8c"),
                            ((.["material-code.colors"].primary // $new_color) + "a0"),
                            ((.["material-code.colors"].primary // $new_color) + "b4")
                        ]
                    else
                        [
                            ((.["material-code.colors"].primary // $new_color) + "20"),
                            ((.["material-code.colors"].primary // $new_color) + "32"),
                            ((.["material-code.colors"].primary // $new_color) + "44"),
                            ((.["material-code.colors"].primary // $new_color) + "56"),
                            ((.["material-code.colors"].primary // $new_color) + "68"),
                            ((.["material-code.colors"].primary // $new_color) + "7a"),
                            ((.["material-code.colors"].primary // $new_color) + "8c"),
                            ((.["material-code.colors"].primary // $new_color) + "9e")
                        ]
                    end)
                end
            )' > "$tmp_settings"; then
            mv "$tmp_settings" "$CODE_SETTINGS_PATH"
        else
            true
            rm -f "$tmp_settings"
        fi
    else
        if printf '%s\n' "$normalized_json" | jq \
            --arg new_color "$new_color" \
            --arg theme_name "$theme_name" \
            --arg mode_flag "$mode_flag" \
            '.["material-code.primaryColor"] = $new_color
            | .["workbench.colorTheme"] = $theme_name
            | .["indentRainbow.colors"] = (
                if $mode_flag == "dark" then
                    [
                        ($new_color + "28"),
                        ($new_color + "3c"),
                        ($new_color + "50"),
                        ($new_color + "64"),
                        ($new_color + "78"),
                        ($new_color + "8c"),
                        ($new_color + "a0"),
                        ($new_color + "b4")
                    ]
                else
                    [
                        ($new_color + "20"),
                        ($new_color + "32"),
                        ($new_color + "44"),
                        ($new_color + "56"),
                        ($new_color + "68"),
                        ($new_color + "7a"),
                        ($new_color + "8c"),
                        ($new_color + "9e")
                    ]
                end
            )' > "$tmp_settings"; then
            mv "$tmp_settings" "$CODE_SETTINGS_PATH"
        else
            rm -f "$tmp_settings"
        fi
    fi
done

