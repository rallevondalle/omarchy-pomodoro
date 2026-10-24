#!/usr/bin/env bash
# Install this checkout as the rallevondalle.pomodoro shell plugin and place
# it right of the clock. For a plain install, `omarchy plugin add` works too.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
PLUGIN_DIR="$CONFIG/omarchy/plugins/rallevondalle.pomodoro"

mkdir -p "$PLUGIN_DIR"
cp "$SRC"/manifest.json "$SRC"/*.qml "$PLUGIN_DIR/"
omarchy plugin validate "$PLUGIN_DIR" >/dev/null

# A freshly copied plugin is only known to the shell after a rescan.
omarchy-shell shell rescanPlugins >/dev/null
for _ in $(seq 20); do
  omarchy-plugin-list | grep -q '^rallevondalle\.pomodoro ' && break
  sleep 0.25
done
omarchy-plugin-enable rallevondalle.pomodoro >/dev/null
jq -e '[.bar.layout[][]?.id] | index("rallevondalle.pomodoro")' "$CONFIG/omarchy/shell.json" >/dev/null 2>&1 \
  || omarchy bar move rallevondalle.pomodoro --after omarchy.clock >/dev/null

# Hot-reload leaves the service's IPC and the panel on the old code.
omarchy restart shell >/dev/null 2>&1
echo "Installed. Right-click the timer next to the clock for the menu."
