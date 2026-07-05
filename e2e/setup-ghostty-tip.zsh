#!/usr/bin/env zsh
# Prepare an isolated Ghostty-tip app bundle and optional live ghostty-zmx dev
# install for E2E/manual testing.
#
# This never installs Homebrew's ghostty@tip cask because that cask conflicts
# with stable Ghostty and targets /Applications/Ghostty.app. Instead it copies
# a downloaded tip DMG's Ghostty.app to /Applications/Ghostty-tip.app, rewrites
# only the copied bundle identity to Ghostty-tip, ad-hoc signs it, and registers
# it with LaunchServices so AppleScript can address "Ghostty-tip".
#
# With --install-live, this also installs the checkout's ghostty-zmx files into
# ~/.config/ghostty-zmx-tip and writes isolated Ghostty-tip config/zdotdir files.
# It never edits stable Ghostty config or global ~/.zshrc / ~/.zprofile.
set -eu

emulate -L zsh
setopt no_sh_word_split

local target="${GZMX_E2E_GHOSTTY_TIP_APP:-/Applications/Ghostty-tip.app}"
local app_name="${GZMX_E2E_GHOSTTY_TIP_NAME:-Ghostty-tip}"
local bundle_id="${GZMX_E2E_GHOSTTY_TIP_BUNDLE_ID:-com.mitchellh.ghostty.tip}"
local dmg="${GZMX_E2E_GHOSTTY_TIP_DMG:-}"
local url="${GZMX_E2E_GHOSTTY_TIP_URL:-}"
local sha="${GZMX_E2E_GHOSTTY_TIP_SHA256:-}"
local replace="${GZMX_E2E_GHOSTTY_TIP_REPLACE:-0}"
local install_live=0
local repo_dir="${0:A:h:h}"
local install_dir="${GZMX_E2E_GHOSTTY_TIP_INSTALL_DIR:-$HOME/.config/ghostty-zmx-tip}"
local tip_config_dir="${GZMX_E2E_GHOSTTY_TIP_CONFIG_DIR:-$HOME/.config/ghostty-tip}"
local tip_zdotdir="${GZMX_E2E_GHOSTTY_TIP_ZDOTDIR:-$HOME/.config/ghostty-tip-zdotdir}"
local tip_config="$tip_config_dir/config.ghostty"
local tip_launcher="$tip_config_dir/open-ghostty-tip.zsh"
local mount_dir=""

usage() {
  cat <<'EOF'
Usage: e2e/setup-ghostty-tip.zsh [--install-live]

Options:
  --install-live                   Install this checkout for Ghostty-tip-only testing

Environment:
  GZMX_E2E_GHOSTTY_TIP_APP       Target app, default /Applications/Ghostty-tip.app
  GZMX_E2E_GHOSTTY_TIP_DMG       Existing Ghostty tip DMG to copy from
  GZMX_E2E_GHOSTTY_TIP_URL       Download URL for Ghostty tip DMG
  GZMX_E2E_GHOSTTY_TIP_SHA256    Optional SHA-256 for the DMG
  GZMX_E2E_GHOSTTY_TIP_REPLACE=1 Replace existing target app before copying
  GZMX_E2E_GHOSTTY_TIP_INSTALL_DIR
                                  Live ghostty-zmx install dir, default ~/.config/ghostty-zmx-tip
  GZMX_E2E_GHOSTTY_TIP_CONFIG_DIR Isolated Ghostty-tip config dir, default ~/.config/ghostty-tip
  GZMX_E2E_GHOSTTY_TIP_ZDOTDIR    Isolated Ghostty-tip ZDOTDIR, default ~/.config/ghostty-tip-zdotdir

If the target app already exists and no DMG/URL is provided, the script only
ensures the copied app has the isolated Ghostty-tip identity and signature.

--install-live copies this checkout into ~/.config/ghostty-zmx-tip, refreshes the
vendored terminfo from /Applications/Ghostty-tip.app, and writes only isolated
Ghostty-tip config/zdotdir files. It never touches stable Ghostty config,
/Applications/Ghostty.app, ~/.zshrc, or ~/.zprofile.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --install-live) install_live=1; shift ;;
    *) print -u2 "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

[[ "$target" == */Ghostty-tip.app ]] || {
  print -u2 "Refusing target that is not named Ghostty-tip.app: $target"
  exit 1
}
[[ "$target" != "/Applications/Ghostty.app" ]] || {
  print -u2 "Refusing to touch stable Ghostty: $target"
  exit 1
}
if [[ -e "/Applications/Ghostty.app" && "${target:A}" == "/Applications/Ghostty.app" ]]; then
  print -u2 "Refusing target that resolves to stable Ghostty: $target"
  exit 1
fi
[[ "$tip_config" != "$HOME/.config/ghostty/config"* ]] || {
  print -u2 "Refusing Ghostty-tip config path under stable Ghostty config: $tip_config"
  exit 1
}
[[ "$tip_config" != "$HOME/Library/Application Support/com.mitchellh.ghostty/"* ]] || {
  print -u2 "Refusing Ghostty-tip config path under stable Ghostty app-support config: $tip_config"
  exit 1
}
[[ "$tip_zdotdir" != "$HOME" && "$tip_zdotdir" != "$HOME/" ]] || {
  print -u2 "Refusing to use HOME as Ghostty-tip ZDOTDIR"
  exit 1
}

cleanup() {
  [[ -n "$mount_dir" && -d "$mount_dir" ]] && hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM HUP

install_live_files() {
  emulate -L zsh
  setopt local_options no_sh_word_split

  local -a required=(
    session-manager.zsh
    session-manager-lib.zsh
    session-manager-early.zsh
    session-manager-v0.1.zsh
    ghostty-zmx
    uninstall.sh
    install-server.sh
    ghostty-zmx-remote-layout
    terminfo/xterm-ghostty.terminfo
  )
  local f
  for f in "${required[@]}"; do
    [[ -r "$repo_dir/$f" ]] || { print -u2 "Missing checkout file: $repo_dir/$f"; exit 1; }
  done

  mkdir -p "$install_dir/terminfo" "$tip_config_dir" "$tip_zdotdir"
  install -m 0644 "$repo_dir/session-manager.zsh" "$install_dir/session-manager.zsh"
  install -m 0644 "$repo_dir/session-manager-lib.zsh" "$install_dir/session-manager-lib.zsh"
  install -m 0644 "$repo_dir/session-manager-early.zsh" "$install_dir/session-manager-early.zsh"
  install -m 0644 "$repo_dir/session-manager-v0.1.zsh" "$install_dir/session-manager-v0.1.zsh"
  install -m 0755 "$repo_dir/ghostty-zmx" "$install_dir/ghostty-zmx"
  install -m 0755 "$repo_dir/uninstall.sh" "$install_dir/uninstall.sh"
  install -m 0755 "$repo_dir/install-server.sh" "$install_dir/install-server.sh"
  install -m 0755 "$repo_dir/ghostty-zmx-remote-layout" "$install_dir/ghostty-zmx-remote-layout"

  local tip_terminfo="$target/Contents/Resources/terminfo"
  if [[ -d "$tip_terminfo" ]] && TERMINFO="$tip_terminfo" infocmp -x xterm-ghostty >"$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null; then
    sed -i '' '1d' "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null || sed -i '1d' "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null
    mv "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" "$install_dir/terminfo/xterm-ghostty.terminfo"
    print "Refreshed vendored terminfo from $target"
  else
    rm -f "$install_dir/terminfo/xterm-ghostty.terminfo.tmp" 2>/dev/null || true
    install -m 0644 "$repo_dir/terminfo/xterm-ghostty.terminfo" "$install_dir/terminfo/xterm-ghostty.terminfo"
    print "Warning: could not read Ghostty-tip terminfo; used checkout terminfo"
  fi

  cat > "$tip_config" <<EOF
# ghostty-tip isolated ghostty-zmx config
env = ZDOTDIR=$tip_zdotdir
env = GHOSTTY_ZMX_AUTO_ATTACH=1
env = GHOSTTY_ZMX_INSTALL_DIR=$install_dir
window-save-state = never
confirm-close-surface = true
EOF

  cat > "$tip_zdotdir/.zprofile" <<EOF
# ghostty-tip isolated zprofile for ghostty-zmx
typeset _gzmx_tip_saved_auto_attach="\${GHOSTTY_ZMX_AUTO_ATTACH-}"
typeset -i _gzmx_tip_had_auto_attach="\${+GHOSTTY_ZMX_AUTO_ATTACH}"
export GHOSTTY_ZMX_AUTO_ATTACH=0
[[ -r "$HOME/.zprofile" ]] && source "$HOME/.zprofile"
if (( _gzmx_tip_had_auto_attach )); then
  export GHOSTTY_ZMX_AUTO_ATTACH="\$_gzmx_tip_saved_auto_attach"
else
  unset GHOSTTY_ZMX_AUTO_ATTACH
fi
unset _gzmx_tip_saved_auto_attach _gzmx_tip_had_auto_attach
[[ -r ${(qqq)install_dir}/session-manager-early.zsh ]] && source ${(qqq)install_dir}/session-manager-early.zsh
EOF

  cat > "$tip_zdotdir/.zshrc" <<EOF
# ghostty-tip isolated zshrc for ghostty-zmx
typeset _gzmx_tip_saved_auto_attach="\${GHOSTTY_ZMX_AUTO_ATTACH-}"
typeset -i _gzmx_tip_had_auto_attach="\${+GHOSTTY_ZMX_AUTO_ATTACH}"
export GHOSTTY_ZMX_AUTO_ATTACH=0
[[ -r "$HOME/.zshrc" ]] && source "$HOME/.zshrc"
if (( _gzmx_tip_had_auto_attach )); then
  export GHOSTTY_ZMX_AUTO_ATTACH="\$_gzmx_tip_saved_auto_attach"
else
  unset GHOSTTY_ZMX_AUTO_ATTACH
fi
unset _gzmx_tip_saved_auto_attach _gzmx_tip_had_auto_attach
[[ -r ${(qqq)install_dir}/session-manager.zsh ]] && source ${(qqq)install_dir}/session-manager.zsh
EOF

  cat > "$tip_launcher" <<EOF
#!/bin/zsh
exec open -na ${(q)target} --args \\
  --config-default-files=false \\
  --config-file=${(q)tip_config}
EOF
  chmod 0755 "$tip_launcher"

  print "Ghostty-tip live ghostty-zmx install ready:"
  print "  install dir: $install_dir"
  print "  config:      $tip_config"
  print "  zdotdir:     $tip_zdotdir"
  print "  launcher:    $tip_launcher"
  print ""
  print "Launch with:"
  print "  $tip_launcher"
  print "or:"
  print "  open -na ${(q)target} --args --config-default-files=false --config-file=${(q)tip_config}"
}

if [[ -n "$url" ]]; then
  dmg="${dmg:-/tmp/Ghostty-tip.dmg}"
  print "Downloading Ghostty tip DMG..."
  curl -L -o "$dmg" "$url"
fi

if [[ -n "$dmg" ]]; then
  [[ -r "$dmg" ]] || { print -u2 "DMG not readable: $dmg"; exit 1; }
  if [[ -n "$sha" ]]; then
    local actual
    actual="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
    [[ "$actual" == "$sha" ]] || {
      print -u2 "SHA-256 mismatch for $dmg"
      print -u2 "expected: $sha"
      print -u2 "actual:   $actual"
      exit 1
    }
  fi

  if [[ -e "$target" ]]; then
    [[ "$replace" == "1" ]] || {
      print -u2 "$target already exists. Set GZMX_E2E_GHOSTTY_TIP_REPLACE=1 to replace it."
      exit 1
    }
    rm -rf "$target"
  fi

  mount_dir="$(mktemp -d /tmp/ghostty-tip-mount-XXXXXX)"
  hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$dmg" >/dev/null
  [[ -d "$mount_dir/Ghostty.app" ]] || { print -u2 "Ghostty.app not found in DMG"; exit 1; }
  ditto "$mount_dir/Ghostty.app" "$target"
fi

[[ -d "$target" ]] || {
  print -u2 "$target does not exist. Provide GZMX_E2E_GHOSTTY_TIP_DMG or GZMX_E2E_GHOSTTY_TIP_URL."
  exit 1
}

plutil -replace CFBundleName -string "$app_name" "$target/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name" "$target/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$bundle_id" "$target/Contents/Info.plist"
codesign --force --deep --sign - "$target" >/dev/null

local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[[ -x "$lsregister" ]] && "$lsregister" -f "$target" >/dev/null 2>&1 || true

print "Ghostty-tip E2E app ready:"
print "  app:       $target"
print "  name:      $(plutil -extract CFBundleName raw "$target/Contents/Info.plist")"
print "  bundle id: $(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"

if [[ "$install_live" == "1" ]]; then
  print ""
  install_live_files
fi
