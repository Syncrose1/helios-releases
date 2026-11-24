#!/bin/bash
# HELIOS's installer, for Linux (Hyprland). Pulls the latest release itself: nothing to download first.
# Run it and choose with the arrow keys:
#   curl -fsSL https://raw.githubusercontent.com/Syncrose1/helios-releases/main/install/install.sh | bash
# Or say what to do (also how it runs with no terminal to ask in):
#   ... | bash -s -- install        install or update
#   ... | bash -s -- uninstall      remove HELIOS, keep your settings and models
#   ... | bash -s -- purge          remove HELIOS and everything it kept
# HELIOS_NO_HYPR=1 skips reloading Hyprland (tests); HELIOS_TARBALL=<file> installs a local build;
# HELIOS_NO_SERVICE=1 skips systemd (tests in a throwaway HOME); HELIOS_NO_PACKAGES=1 only lists
# missing system packages (never runs pacman).
set -euo pipefail

REPO="Syncrose1/helios-releases"
REL="https://github.com/$REPO/releases/latest/download"
ASSET="helios-linux-x64.tar.gz"
B=$'\033[1m'; D=$'\033[2m'; G=$'\033[38;5;220m'; Y=$'\033[38;5;208m'; R=$'\033[0m'
say() { printf '%s%s%s\n' "$B" "$*" "$R"; }
tmp="$(mktemp -d)"
cleanup() { { printf '\033[?25h' >/dev/tty; } 2>/dev/null || true; rm -rf "$tmp"; }
trap cleanup EXIT
trap 'exit 130' INT

OPT="$HOME/.local/opt/helios"
BIN="$HOME/.local/bin/helios"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR="$CONF/hypr"
UNIT="$CONF/systemd/user/helios.service"
MARK_BEGIN="-- >>> HELIOS (added by its installer; removed by its uninstaller)"
MARK_END="-- <<< HELIOS"
data_dirs() { printf '%s\n' "$CONF/helios" "${XDG_DATA_HOME:-$HOME/.local/share}/helios"; }
has_tty() { { : </dev/tty; } 2>/dev/null; }
systemd_ok() { [ -z "${HELIOS_NO_SERVICE:-}" ] && command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; }

installed_version() { [ -x "$OPT/helios" ] && { cat "$OPT/VERSION" 2>/dev/null || echo "?"; }; return 0; }
latest_version() { curl -fsSL --max-time 5 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1; }

# Hyprland loads ~/.config/hypr/user/helios.lua. Syn's Noctalia's shared.lua already looks for it;
# anywhere else, a marked block at the end of hyprland.lua does (and only that block is ever touched).
hook_hypr() {
  local main="$HYPR/hyprland.lua" shared="$HYPR/user/shared.lua"
  if [ -f "$shared" ] && [ "$(grep -cF -- 'user/helios.lua' "$shared" || true)" != 0 ]; then return 0; fi
  if [ ! -f "$main" ]; then
    echo "  No ~/.config/hypr/hyprland.lua (HELIOS needs Hyprland's Lua config, 0.55+): load $HYPR/user/helios.lua yourself."
    return 0
  fi
  [ "$(grep -cF -- "$MARK_BEGIN" "$main" || true)" != 0 ] && return 0
  printf '\n%s\ndo local f = os.getenv("HOME") .. "/.config/hypr/user/helios.lua"; local h = io.open(f, "r"); if h then h:close(); dofile(f) end end\n%s\n' \
    "$MARK_BEGIN" "$MARK_END" >> "$main"
  echo "  Added a HELIOS block to the end of hyprland.lua."
}
unhook_hypr() {
  local main="$HYPR/hyprland.lua"
  [ -f "$main" ] && [ "$(grep -cF -- "$MARK_BEGIN" "$main" || true)" != 0 ] || return 0
  sed -i "\|^$MARK_BEGIN\$|,\|^$MARK_END\$|d" "$main"
  echo "  Removed the HELIOS block from hyprland.lua."
}
reload_hypr() {
  [ -z "${HELIOS_NO_HYPR:-}" ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && command -v hyprctl >/dev/null 2>&1 || return 0
  hyprctl reload >/dev/null 2>&1 && echo "  Reloaded Hyprland." || true
}

# What HELIOS runs, by the command it calls: command, package (Arch / CachyOS), what it's for.
PACKAGES="
qs quickshell the overlays: island, radial, answers
grim grim screenshots (Ask, Point)
tesseract tesseract reading text on screen (Point)
- tesseract-data-eng English for tesseract
magick imagemagick preparing screenshots for Point
wtype wtype typing dictation into windows
wl-copy wl-clipboard copying
cliphist cliphist clipboard history
bsdtar libarchive unpacking the speech models
xdg-open xdg-utils opening files and links
chromium chromium HELIOS's browser
pw-cat pipewire playing sound (the voice)
uv uv the voice engine's Python
"

# Anything missing is listed with what it's for; with your go-ahead (and your sudo password), the
# system is updated first and the packages installed in the same step: pacman -Syu --needed.
# (Never a bare -S on an old package database: on Arch that's a partial upgrade.)
ensure_packages() {
  command -v pacman >/dev/null 2>&1 || return 0
  local missing=() why=() manual=() cmd pkg about
  while read -r cmd pkg about; do
    [ -n "${cmd:-}" ] || continue
    if [ "$cmd" = - ]; then pacman -Qq "$pkg" >/dev/null 2>&1 && continue
    else command -v "$cmd" >/dev/null 2>&1 && continue; fi
    if pacman -Si "$pkg" >/dev/null 2>&1; then missing+=("$pkg"); why+=("$about")
    else manual+=("$pkg ($about)"); fi
  done <<< "$PACKAGES"
  if [ ${#missing[@]} = 0 ] && [ ${#manual[@]} = 0 ]; then
    echo "  Everything HELIOS needs is installed."; return 0
  fi
  local i
  for i in "${!missing[@]}"; do printf '  %-20s %s%s%s\n' "${missing[$i]}" "$D" "${why[$i]}" "$R"; done
  for i in "${manual[@]}"; do printf '  %s%s: not in your repositories, install it yourself (AUR)%s\n' "$Y" "$i" "$R"; done
  [ ${#missing[@]} = 0 ] && return 0
  local run="sudo pacman -Syu --needed ${missing[*]}"
  if [ -n "${HELIOS_NO_PACKAGES:-}" ] || ! has_tty; then
    echo "  To install them (updating the system first):  $run"; return 0
  fi
  echo "  ${D}Installing needs your password (sudo), and updates the whole system first, so nothing is"
  echo "  left half-updated. HELIOS works without these, but the parts listed won't.${R}"
  menu "Update the system and install them now?" "Update and install" "Skip"
  [ "$CHOICE" = 0 ] || { echo "  Skipped: later, run  $run"; return 0; }
  if sudo pacman -Syu --needed "${missing[@]}" </dev/tty; then
    echo "  Installed."
  else
    echo "  ${Y}That didn't finish.${R} HELIOS installs anyway; run  $run  when you can."
  fi
}

# Speech models for dictation (Parakeet + MedASR, about 600 MB), fetched by HELIOS itself.
ensure_speech() {

  if [ -d "${XDG_DATA_HOME:-$HOME/.local/share}/helios/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8" ]; then
    echo "  The speech models are here."; return 0
  fi
  if ! has_tty; then
    echo "  Dictation needs its speech models (about 600 MB): run  helios dictate download"; return 0
  fi
  menu "Download the speech models for dictation now (about 600 MB)?" "Download" "Later"
  [ "$CHOICE" = 0 ] || { echo "  Later: run  helios dictate download"; return 0; }
  "$BIN" dictate download </dev/tty || echo "  It didn't finish: run  helios dictate download  to resume."
}

# The voice that reads aloud (LuxTTS on the CPU, about 2 GB), set up by HELIOS's own script.
ensure_voice() {
  local setup="$OPT/data/voice/setup.sh"
  [ -x "$setup" ] || return 0
  if "$setup" --check; then
    "$setup" >/dev/null 2>&1 || true   # (copies in any new voices)
    echo "  The voice engine is here."; return 0
  fi
  if ! has_tty; then
    echo "  Reading aloud needs its voice engine (about 2 GB): run  $setup"; return 0
  fi
  menu "Set up the voice for reading aloud now (about 2 GB)?" "Set up" "Later"
  [ "$CHOICE" = 0 ] || { echo "  Later: run  $setup"; return 0; }
  "$setup" </dev/tty || echo "  It didn't finish: run  $setup  to resume."
}

# Priority: HELIOS (its hub and the overlay that draws the radial and the launcher) should come
# before your other work when the machine is busy. Process-priority managers match by name, and
# CachyOS's ananicy rules put every "qs" (Quickshell) in its Service class, nice 10: the radial ends
# up starved. The overlay runs as "helios-overlay"; this gives it, and the hub, their own rule.
PRIORITY_RULE='# HELIOS: its hub, its overlay and its radial answer first. Written by its installer.
{ "name": "helios", "nice": -6, "ioclass": "best-effort", "ionice": 2 }
{ "name": "helios-overlay", "nice": -6, "ioclass": "best-effort", "ionice": 2 }
{ "name": "helios-radial", "nice": -6, "ioclass": "best-effort", "ionice": 2 }'
PRIORITY_FILE=/etc/ananicy.d/helios.rules
ananicy_unit() { local u; for u in ananicy-cpp ananicy; do systemctl list-unit-files "$u.service" >/dev/null 2>&1 && systemctl is-enabled "$u.service" >/dev/null 2>&1 && { echo "$u"; return 0; }; done; return 1; }
ensure_priority() {
  local unit
  if unit="$(ananicy_unit)" && [ -d /etc/ananicy.d ]; then
    if [ -f "$PRIORITY_FILE" ] && [ "$(cat "$PRIORITY_FILE")" = "$PRIORITY_RULE" ]; then
      echo "  HELIOS's priority rule is in place ($unit)."; return 0
    fi
    echo "  $unit manages process priority here, and by default it would run HELIOS's overlay"
    echo "  in the background. A rule for HELIOS (its hub, overlay and radial only) fixes that."
    if [ -n "${HELIOS_NO_PACKAGES:-}" ] || ! has_tty; then
      echo "  To add it, run this installer again in a terminal (it asks for your password)."; return 0
    fi
    menu "Add HELIOS's priority rule (needs your password)?" "Add it" "Skip"
    [ "$CHOICE" = 0 ] || { echo "  Skipped: the radial may lag when the machine is busy."; return 0; }
    # The password first, from the terminal (sudo -v); then the rule goes in through the pipe.
    # (Giving `sudo tee` the terminal as its input made tee read the keyboard instead of the rule.)
    if sudo -v </dev/tty && printf '%s\n' "$PRIORITY_RULE" | sudo tee "$PRIORITY_FILE" >/dev/null && sudo systemctl restart "$unit" </dev/tty; then
      echo "  Added."
    else
      echo "  ${Y}That didn't finish.${R} HELIOS works anyway; it may lag when the machine is busy."
    fi
    return 0
  fi
  if systemctl is-active com.system76.Scheduler.service >/dev/null 2>&1; then
    echo "  ${Y}system76-scheduler manages process priority here.${R} HELIOS doesn't change its config itself:"
    echo "  to keep the radial responsive, give the processes  helios  and  helios-overlay  a high priority there."
    return 0
  fi
  echo "  No priority manager to configure: HELIOS's service asks for its share itself."
}

remove_priority() {
  [ -f "$PRIORITY_FILE" ] || return 0
  local unit; unit="$(ananicy_unit || echo ananicy-cpp)"
  if has_tty; then
    menu "Remove HELIOS's priority rule from $PRIORITY_FILE (needs your password)?" "Remove it" "Leave it"
    if [ "$CHOICE" = 0 ] && sudo rm -f "$PRIORITY_FILE" </dev/tty; then
      sudo systemctl restart "$unit" </dev/tty 2>/dev/null || true
      echo "  Removed its priority rule."; return 0
    fi
  fi
  echo "  Its priority rule stays: remove it with  sudo rm $PRIORITY_FILE && sudo systemctl restart $unit"
}

do_uninstall() {   # $1 = purge to remove settings and models too
  local found=""
  if systemd_ok; then systemctl --user disable --now helios.service >/dev/null 2>&1 || true; fi
  [ -f "$UNIT" ] && { rm -f "$UNIT"; systemd_ok && systemctl --user daemon-reload || true; }
  [ -e "$OPT" ] && { rm -rf "$OPT"; say "Removed $OPT"; found=1; }
  # (older versions put themes in Kando's folders: tidy those away)
  rm -rf "$CONF/kando/menu-themes/helios" "$CONF/kando/sound-themes/helios" 2>/dev/null || true
  [ -L "$BIN" ] && rm -f "$BIN"
  [ -f "$HYPR/user/helios.lua" ] && { rm -f "$HYPR/user/helios.lua"; echo "  Removed its Hyprland bindings."; }
  remove_priority
  unhook_hypr
  reload_hypr
  [ -n "$found" ] || say "HELIOS wasn't installed here, so there was nothing to remove."
  if [ "${1:-}" = purge ]; then
    while IFS= read -r p; do [ -e "$p" ] && { rm -rf "$p"; say "Removed $p"; }; done < <(data_dirs)
    say "HELIOS and everything it kept are gone."
  else
    echo "Your settings and models are kept, ready if you install again."
  fi
}

do_install() {
  [ "$(uname -s)" = Linux ] || { echo "HELIOS is for Linux (Hyprland)." >&2; exit 1; }
  [ "$(uname -m)" = x86_64 ] || { echo "HELIOS is built for x86_64 only, for now." >&2; exit 1; }
  say "System packages"
  ensure_packages

  say "Priority"
  ensure_priority

  if [ -n "${HELIOS_TARBALL:-}" ]; then
    say "Installing the local build $HELIOS_TARBALL"
    cp "$HELIOS_TARBALL" "$tmp/$ASSET"
  else
    say "Downloading HELIOS"
    curl -fL --progress-bar -o "$tmp/$ASSET" "$REL/$ASSET"
  fi
  mkdir -p "$tmp/x" && tar -xzf "$tmp/$ASSET" -C "$tmp/x"
  [ -x "$tmp/x/helios/helios" ] || { echo "The download didn't contain HELIOS." >&2; exit 1; }

  say "Installing into $OPT"
  mkdir -p "$(dirname "$OPT")" && rm -rf "$OPT.new" && mv "$tmp/x/helios" "$OPT.new"
  rm -rf "$OPT" && mv "$OPT.new" "$OPT"      # the running hub keeps its old file until it restarts
  mkdir -p "$(dirname "$BIN")" && ln -sfn "$OPT/helios" "$BIN"

  # settings: written once, never overwritten
  mkdir -p "$CONF/helios"
  [ -f "$CONF/helios/config.toml" ] || { cp "$OPT/data/config.toml" "$CONF/helios/config.toml"; echo "  Settings: $CONF/helios/config.toml"; }

  say "Hooking into Hyprland"
  mkdir -p "$HYPR/user" && cp "$OPT/data/hypr/helios.lua" "$HYPR/user/helios.lua"
  hook_hypr
  reload_hypr

  say "Dictation"
  ensure_speech

  say "Voice"
  ensure_voice

  if systemd_ok; then
    say "Starting the hub"
    mkdir -p "$(dirname "$UNIT")" && cp "$OPT/data/systemd/helios.service" "$UNIT"
    systemctl --user daemon-reload
    systemctl --user enable helios.service >/dev/null 2>&1 || true
    systemctl --user restart helios.service
    sleep 0.5
  fi

  say "${G}HELIOS is installed:${R}${B} $BIN"
  "$BIN" status 2>/dev/null | sed 's/^/  /' || true
  echo "Super+H: the radial at your pointer. Move through an item to choose it; Esc dismisses."
  echo "Run the same line again any time to update or uninstall."
  if ! command -v claude >/dev/null 2>&1 && ! command -v codex >/dev/null 2>&1 && ! [ -x "$HOME/.grok/bin/grok" ]; then
    echo "For AI, sign in to one of Claude Code, Codex or Grok Build, or run a local model on port 8081."
  fi
}

# ── the menu: up/down (or j/k, or a number) to move, Enter to choose, Esc or q to leave ──
CHOICE=0
menu() {   # menu <question> <option>...: sets CHOICE to the chosen index (the last option on Esc)
  local q="$1"; shift; local opts=("$@") n=$# i key rest w=0 o
  for o in "${opts[@]}"; do [ ${#o} -gt $w ] && w=${#o}; done
  CHOICE=0
  printf '\033[?25l' >/dev/tty
  draw() {
    printf '  %s%s%s\n' "$B" "$q" "$R" >/dev/tty
    for i in "${!opts[@]}"; do
      if [ "$i" = "$CHOICE" ]; then printf '    %s%-*s  [•]  ←%s\n' "$G$B" "$w" "${opts[$i]}" "$R" >/dev/tty
      else printf '    %-*s  %s[ ]%s\n' "$w" "${opts[$i]}" "$D" "$R" >/dev/tty; fi
    done
    printf '%s    ↑ ↓ to move · Enter to choose · Esc to leave%s\n' "$D" "$R" >/dev/tty
  }
  draw
  while :; do
    IFS= read -rsn1 key </dev/tty || key=q
    case "$key" in
      $'\x1b') rest=""; IFS= read -rsn2 -t 0.05 rest </dev/tty || true
               case "$rest" in '[A') CHOICE=$(( (CHOICE + n - 1) % n ));; '[B') CHOICE=$(( (CHOICE + 1) % n ));; '') CHOICE=$((n - 1)); break;; esac ;;
      k) CHOICE=$(( (CHOICE + n - 1) % n ));;
      j) CHOICE=$(( (CHOICE + 1) % n ));;
      [1-9]) [ "$key" -le "$n" ] && CHOICE=$((key - 1));;
      q) CHOICE=$((n - 1)); break;;
      '') break;;
    esac
    printf '\033[%dA\033[J' $((n + 2)) >/dev/tty
    draw
  done
  printf '\033[?25h' >/dev/tty
  echo >/dev/tty
}

# the name, big, in sunlight (and plain on a terminal too narrow for it)
banner() {
  local cols shades=(196 202 208 214 220 226) i=0 line
  cols="$( { tput cols </dev/tty; } 2>/dev/null || echo 80)"
  echo >/dev/tty
  if [ "$cols" -ge 50 ]; then
    while IFS= read -r line; do printf '  \033[38;5;%sm%s%s\n' "${shades[$i]}" "$line" "$R" >/dev/tty; i=$((i + 1)); done <<'ART'
██╗  ██╗███████╗██╗     ██╗ ██████╗ ███████╗
██║  ██║██╔════╝██║     ██║██╔═══██╗██╔════╝
███████║█████╗  ██║     ██║██║   ██║███████╗
██╔══██║██╔══╝  ██║     ██║██║   ██║╚════██║
██║  ██║███████╗███████╗██║╚██████╔╝███████║
╚═╝  ╚═╝╚══════╝╚══════╝╚═╝ ╚═════╝ ╚══════╝
ART
    printf '  %*s%s%s%s\n' 10 '' "$D" "By Syncra (Raahat Shah)" "$R" >/dev/tty
  else
    printf '  %sH E L I O S%s\n  %sBy Syncra (Raahat Shah)%s\n' "$G$B" "$R" "$D" "$R" >/dev/tty
  fi
}

interactive() {
  local have latest state
  have="$(installed_version)"; latest="$(latest_version || true)"
  if [ -z "$have" ]; then state="Not installed on this computer${latest:+ · latest is v$latest}"
  elif [ -n "$latest" ] && [ "$have" = "$latest" ]; then state="Installed: v$have, up to date"
  else state="Installed: v$have${latest:+ · v$latest is out}"; fi
  banner
  printf '\n  %sHELIOS%s · %s%s%s\n\n' "$B" "$R" "$D" "$state" "$R" >/dev/tty
  while :; do
    menu "What would you like to do?" \
      "Install or update HELIOS" \
      "Uninstall HELIOS but keep my settings and models" \
      "Uninstall HELIOS completely" \
      "Exit"
    case "$CHOICE" in
      0) do_install; return;;
      1) do_uninstall; return;;
      2) printf '  %sThis also deletes your HELIOS settings, models, history and browser profile.%s\n\n' "$Y" "$R" >/dev/tty
         menu "Remove everything?" "Yes, remove HELIOS and everything it kept" "No, go back"
         if [ "$CHOICE" = 0 ]; then do_uninstall purge; return; fi ;;
      *) echo "Nothing changed."; return;;
    esac
  done
}

case "${1:-}" in
  install|update) do_install ;;
  uninstall) if [ "${2:-}" = --purge ]; then do_uninstall purge; else do_uninstall; fi ;;
  purge) do_uninstall purge ;;
  "") if has_tty; then interactive; else do_install; fi ;;   # no terminal to ask in: install
  *) echo "Use: install, uninstall or purge (or nothing, to choose from a menu)" >&2; exit 2 ;;
esac
