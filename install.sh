#!/usr/bin/env bash
# dotfiles installer
# Supports Debian/Ubuntu, CentOS/RHEL/Fedora, and macOS.
# Usage:
#   ./install.sh              # full flow: timezone + tools + optional + link + tmux plugins
#   ./install.sh timezone     # set the system timezone only
#   ./install.sh tools        # install missing required tools only
#   ./install.sh optional     # install missing optional tools only
#   ./install.sh link         # create symlinks and source bash/.workrc from ~/.bashrc
#   ./install.sh tmux-plugins # install tmux plugins only

set -euo pipefail

# Repo root (directory containing this script).
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Required tools: install unconditionally when missing.
# `curl` is used by the upstream Go installer, so it must be in this set.
REQUIRED_TOOLS=(vim tmux fzf curl)

# Optional tools: install when missing, but a failure is not fatal.
# `go` is handled separately via install_go_from_upstream (installs the official
# upstream tarball to /usr/local/go, not the distro-packaged version).
# `tldr` is handled separately via pipx (uniform across Debian/RHEL, avoids
# EPEL/tealdeer/legacy-`tldr` package hunting).
OPTIONAL_TOOLS=(git make docker python3)

# ---------- Output helpers ----------
log()  { printf '\033[1;34m[dotfiles]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[dotfiles]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[dotfiles]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- Platform detection ----------
# Prints one of: debian | rhel | macos
detect_os() {
  local uname_s
  uname_s="$(uname -s)"
  if [[ "$uname_s" == "Darwin" ]]; then
    echo macos
    return
  fi
  if [[ "$uname_s" != "Linux" ]]; then
    die "unsupported OS: $uname_s"
  fi
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*ubuntu*) echo debian ;;
      *rhel*|*centos*|*fedora*|*rocky*|*almalinux*|*tencentos*) echo rhel ;;
      *) die "unsupported Linux distro: ID=${ID:-} ID_LIKE=${ID_LIKE:-}" ;;
    esac
  else
    die "cannot detect Linux distro (missing /etc/os-release)"
  fi
}

# Emit "sudo" when privilege escalation is needed, empty otherwise.
# macOS is not exempt: `systemsetup -settimezone` and writing /usr/local/go both
# need root there. Homebrew is the exception and is invoked without $sudo.
# Returns non-zero (instead of calling die) when escalation is impossible: this
# runs inside `$(...)`, where die's `exit` would only kill the subshell and let
# the caller continue with an empty sudo. Callers must use `|| return 1`.
sudo_cmd() {
  if [[ "$(id -u)" -eq 0 ]]; then
    echo ""
  else
    if ! command -v sudo >/dev/null 2>&1; then
      warn "need root privileges but sudo is not installed (run as root)"
      return 1
    fi
    echo "sudo"
  fi
}

# ---------- Executability probe ----------
# `command -v` only resolves a name on $PATH and checks the +x bit; it never
# execs, so it cannot see a dead shebang. A pipx venv left behind by a $HOME
# move is the common case: ~/.local/bin/tldr still resolves and is executable,
# but its interpreter path is gone and bash reports the misleading
# "cannot execute: required file not found" at exec time. So actually run the
# tool. A tool that is present but fails this probe is treated as missing and
# reinstalled.
tool_works() {
  local tool="$1"
  command -v "$tool" >/dev/null 2>&1 || return 1
  case "$tool" in
    tmux) tmux -V    >/dev/null 2>&1 ;;  # tmux has no --version
    go)   go version >/dev/null 2>&1 ;;  # go uses a subcommand, not a flag
    *)    "$tool" --version >/dev/null 2>&1 ;;
  esac
}

# ---------- Package installation ----------
# apt-get update only needs to run once per invocation, not once per package.
APT_UPDATED=0

# Map a tool name to the actual package name per distro.
pkg_name_for() {
  local os="$1" tool="$2"
  case "$os:$tool" in
    debian:docker)  echo docker.io ;;  # Debian/Ubuntu's official package is docker.io.
    rhel:docker)    echo docker ;;     # RHEL family; upstream docker-ce would need an extra repo.
    macos:docker)   echo docker ;;     # Homebrew CLI only; the Desktop app is a cask.
    debian:python3) echo python3 ;;    # Generic meta pulls current stable + adds /usr/bin/python3.
    rhel:python3)   rhel_python_pkg ;; # Newest available python3.X module/package.
    macos:python3)  echo python ;;     # Homebrew `python` is the current stable python3.
    *:*)            echo "$tool" ;;
  esac
}

# On dnf/yum: prefer the highest available python3.X module/package.
# Runs unprivileged: listing packages needs no root, and prompting for a sudo
# password inside a command substitution would swallow the prompt.
rhel_python_pkg() {
  local names best
  # dnf wants `list --available`; yum only understands the positional `list available`.
  if command -v dnf >/dev/null 2>&1; then
    names="$(dnf list --available 'python3.[0-9]*' 2>/dev/null || true)"
  else
    names="$(yum list available 'python3.[0-9]*' 2>/dev/null || true)"
  fi
  # Rows look like `python3.12.x86_64  3.12.1-2.el9  appstream`; strip only the
  # trailing arch so python3.12 survives, then pick the highest minor version.
  names="$(printf '%s\n' "$names" \
             | awk '$1 ~ /^python3\.[0-9]+\./ {sub(/\.[^.]*$/, "", $1); print $1}' \
             | sort -u)"
  if [[ -n "$names" ]]; then
    best="$(printf '%s\n' "$names" | sort -t. -k2,2n | tail -1)"
    [[ -n "$best" ]] && { echo "$best"; return; }
  fi
  echo python3
}

install_pkg() {
  local os="$1" pkg="$2"
  local sudo; sudo="$(sudo_cmd)" || return 1
  case "$os" in
    debian)
      # Server target: DEBIAN_FRONTEND=noninteractive silences debconf prompts
      # (e.g. tzdata asking for a geographic area); --no-install-recommends
      # keeps GUI/X11 Recommends out of the closure.
      # Use `env VAR=val cmd` (not `VAR=val cmd`): bash's assignment-prefix
      # syntax is not recognized when the first token is `$sudo` and expands to empty.
      if [[ "$APT_UPDATED" != "1" ]]; then
        $sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq
        APT_UPDATED=1
      fi
      $sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$pkg"
      ;;
    rhel)
      # EPEL is needed for fzf/tealdeer on RHEL/CentOS/Rocky/Alma; safe if already enabled.
      if command -v dnf >/dev/null 2>&1; then
        $sudo dnf install -y epel-release || true
        $sudo dnf install -y "$pkg"
      else
        $sudo yum install -y epel-release || true
        $sudo yum install -y "$pkg"
      fi
      ;;
    macos)
      command -v brew >/dev/null 2>&1 || { warn "Homebrew not found. Install from https://brew.sh"; return 1; }
      brew install "$pkg"
      ;;
    *)
      # Guards against an empty $os from a failed detect_os, which would
      # otherwise fall through the case and report success without installing.
      warn "install_pkg: unknown OS '$os'"
      return 1
      ;;
  esac
}

# Install a list of tools. When $2 is "optional", failures are logged but not fatal.
install_tool_list() {
  local mode="$1"; shift
  local tools=("$@")
  local os; os="$(detect_os)" || return 1
  log "detected OS: $os (mode: $mode)"
  for tool in "${tools[@]}"; do
    if tool_works "$tool"; then
      log "✓ $tool already installed ($(command -v "$tool"))"
      continue
    fi
    if command -v "$tool" >/dev/null 2>&1; then
      warn "$tool is on PATH ($(command -v "$tool")) but fails to run; reinstalling"
    fi
    local pkg; pkg="$(pkg_name_for "$os" "$tool")"
    log "installing $tool (package: $pkg)…"
    if [[ "$mode" == "optional" ]]; then
      install_pkg "$os" "$pkg" || warn "optional tool $tool failed to install, continuing"
    else
      install_pkg "$os" "$pkg"
    fi
  done
}

# ---------- Step 0: system timezone ----------
# Ensure the OS reports Singapore time system-wide (logs, cron, date, all users).
# Idempotent: no-op when the current zone already matches.
TIMEZONE="Asia/Singapore"

step_timezone() {
  local current
  current="$(current_timezone)"
  if [[ "$current" == "$TIMEZONE" ]]; then
    log "✓ system timezone already $TIMEZONE"
    return
  fi
  log "setting system timezone to $TIMEZONE (was: ${current:-unknown})…"
  set_system_timezone "$TIMEZONE" || warn "failed to set system timezone, continuing"
}

current_timezone() {
  # Prefer timedatectl on Linux; fall back to readlink /etc/localtime, then macOS.
  if command -v timedatectl >/dev/null 2>&1; then
    timedatectl show --value --property=Timezone 2>/dev/null && return
  fi
  if [[ -L /etc/localtime ]]; then
    # /etc/localtime -> /usr/share/zoneinfo/Asia/Singapore
    readlink /etc/localtime | sed -E 's|.*/zoneinfo/||'
    return
  fi
  if [[ "$(uname -s)" == "Darwin" ]]; then
    systemsetup -gettimezone 2>/dev/null | sed -E 's/^Time Zone: //'
    return
  fi
  echo ""
}

set_system_timezone() {
  local tz="$1" sudo zonefile os
  sudo="$(sudo_cmd)" || return 1

  case "$(uname -s)" in
    Linux)
      # timedatectl is the systemd path; on non-systemd or containers, fall back to symlinks.
      if command -v timedatectl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        $sudo timedatectl set-timezone "$tz" && return
      fi
      zonefile="/usr/share/zoneinfo/$tz"
      # Minimal server/container images (e.g. ubuntu:22.04) ship without tzdata,
      # so pull it in rather than giving up on the timezone entirely.
      if [[ ! -f "$zonefile" ]]; then
        log "zoneinfo file missing ($zonefile); installing tzdata…"
        os="$(detect_os)" || return 1
        install_pkg "$os" tzdata || { warn "failed to install tzdata"; return 1; }
      fi
      [[ -f "$zonefile" ]] || { warn "zoneinfo file still missing after installing tzdata: $zonefile"; return 1; }
      $sudo ln -sf "$zonefile" /etc/localtime
      # /etc/timezone is Debian's plaintext record; RHEL ignores it but writing it is harmless.
      echo "$tz" | $sudo tee /etc/timezone >/dev/null 2>&1 || true
      ;;
    Darwin)
      $sudo systemsetup -settimezone "$tz" >/dev/null
      ;;
    *)
      warn "unsupported OS for timezone setup: $(uname -s)"
      return 1
      ;;
  esac
}

# ---------- Step 1: required tools ----------
step_tools()    { install_tool_list required "${REQUIRED_TOOLS[@]}"; }

# ---------- Step 2: optional tools ----------
step_optional() {
  install_tool_list optional "${OPTIONAL_TOOLS[@]}"
  step_tldr
  step_go
}

# ---------- Step 2a: tldr via pipx ----------
# pipx installs a per-tool venv into ~/.local/pipx and drops a shim into ~/.local/bin.
# We install `tldr` (the Python client on PyPI). PATH wiring for ~/.local/bin
# lives in the shell rc block written by link_shell_rc_paths.
step_tldr() {
  if tool_works tldr; then
    log "✓ tldr already installed ($(command -v tldr))"
    return
  fi
  if command -v tldr >/dev/null 2>&1; then
    # Present but not runnable: almost always a pipx venv whose shebang points at
    # a stale $HOME. `pipx reinstall` rebuilds it against the current $HOME.
    warn "tldr is on PATH ($(command -v tldr)) but fails to run (stale pipx venv?); reinstalling"
    if command -v pipx >/dev/null 2>&1 && pipx reinstall tldr && tool_works tldr; then
      log "✓ tldr reinstalled via pipx"
      return
    fi
    warn "pipx reinstall did not fix tldr; falling back to a fresh install"
  fi
  install_tldr_via_pipx || warn "optional tool tldr failed to install, continuing"
}

install_tldr_via_pipx() {
  local os; os="$(detect_os)" || return 1
  if ! tool_works pipx; then
    log "installing pipx (needed for tldr)…"
    # The package is named `pipx` on Debian, RHEL/EPEL and Homebrew alike.
    install_pkg "$os" pipx || { warn "failed to install pipx"; return 1; }
  fi
  # pipx run as the invoking user; ensurepath is idempotent.
  pipx install tldr || return 1
  pipx ensurepath >/dev/null 2>&1 || true
  log "✓ tldr installed via pipx (binary lands at \$HOME/.local/bin/tldr)"
}

# ---------- Step 2b: upstream Go ----------
# Install the latest stable Go per https://go.dev/doc/install:
#   1. Query go.dev/VERSION?m=text for the current stable tag.
#   2. Download the matching linux-<arch>.tar.gz / darwin-<arch>.tar.gz.
#   3. Remove /usr/local/go and extract fresh into /usr/local.
# PATH wiring lives in bash/.workrc so the login shell picks it up.
step_go() {
  local existing
  existing="$(command -v go 2>/dev/null || true)"
  if tool_works go; then
    log "✓ go already installed ($existing, $(go version 2>/dev/null))"
    return
  fi
  if [[ -n "$existing" ]]; then
    warn "go is on PATH ($existing) but fails to run; reinstalling from upstream"
  fi
  install_go_from_upstream || warn "optional tool go failed to install, continuing"
}

install_go_from_upstream() {
  command -v curl >/dev/null 2>&1 || die "curl is required to install go"
  command -v tar  >/dev/null 2>&1 || die "tar is required to install go"

  local goos goarch version url tmp sudo
  sudo="$(sudo_cmd)" || return 1

  case "$(uname -s)" in
    Linux)  goos=linux ;;
    Darwin) goos=darwin ;;
    *) warn "go upstream install: unsupported OS $(uname -s)"; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) goarch=amd64 ;;
    aarch64|arm64) goarch=arm64 ;;
    armv6l|armv7l) goarch=armv6l ;;
    i386|i686)     goarch=386 ;;
    *) warn "go upstream install: unsupported arch $(uname -m)"; return 1 ;;
  esac

  version="$(curl -fsSL https://go.dev/VERSION?m=text 2>/dev/null | head -1)"
  [[ "$version" == go* ]] || { warn "could not fetch latest go version from go.dev"; return 1; }
  url="https://go.dev/dl/${version}.${goos}-${goarch}.tar.gz"

  log "installing $version from $url"
  tmp="$(mktemp -d)"
  # No RETURN trap here: RETURN traps aren't function-local, so a trap armed on
  # an early-return path stays installed and re-fires on every later function
  # return. Clean up explicitly on each exit path instead.
  if ! curl -fsSL "$url" -o "$tmp/go.tar.gz"; then
    rm -rf "$tmp"
    warn "download failed: $url"
    return 1
  fi

  # go.dev instructions: rm the old tree first, don't untar over it.
  if ! { $sudo rm -rf /usr/local/go && $sudo tar -C /usr/local -xzf "$tmp/go.tar.gz"; }; then
    rm -rf "$tmp"
    warn "failed to extract $version into /usr/local"
    return 1
  fi
  rm -rf "$tmp"
  log "✓ extracted to /usr/local/go — run 'make link' if $HOME/.bashrc doesn't yet have the go PATH block"
}

# ---------- Step 3: symlinks ----------
# $1 source file (inside the repo), $2 target path (under $HOME).
link_file() {
  local src="$1" dst="$2"
  if [[ -L "$dst" ]]; then
    local cur; cur="$(readlink "$dst")"
    if [[ "$cur" == "$src" ]]; then
      log "✓ $dst -> $src (already linked)"
      return
    fi
    warn "$dst is a symlink to $cur, replacing"
    rm -f "$dst"
  elif [[ -e "$dst" ]]; then
    local backup="${dst}.backup.$(uname -s | tr '[:upper:]' '[:lower:]').$$"
    warn "$dst exists, backing up to $backup"
    mv "$dst" "$backup"
  fi
  ln -s "$src" "$dst"
  log "✓ linked $dst -> $src"
}

step_link() {
  link_file "$DOTFILES_DIR/tmux/.tmux.conf" "$HOME/.tmux.conf"
  link_file "$DOTFILES_DIR/vim/.vimrc"      "$HOME/.vimrc"
  link_bashrc
  link_shell_rc_paths
  link_fzf_init
}

# Idempotent: appends a marker + source line to ~/.bashrc once. We don't copy
# the file, so future edits to bash/.workrc take effect without re-running.
link_bashrc() {
  local bashrc="$HOME/.bashrc"
  local src="$DOTFILES_DIR/bash/.workrc"
  local marker="# >>> dotfiles: source bash/.workrc >>>"
  local endmarker="# <<< dotfiles: source bash/.workrc <<<"

  [[ -f "$src" ]] || die "workrc source file not found: $src"
  touch "$bashrc"

  if grep -Fq "$marker" "$bashrc"; then
    log "✓ $bashrc already sources $src"
    return
  fi
  {
    printf '\n%s\n' "$marker"
    printf '[ -f %q ] && . %q\n' "$src" "$src"
    printf '%s\n' "$endmarker"
  } >> "$bashrc"
  log "✓ appended source line for $src to $bashrc"
}

# Idempotent: adds Go and pipx PATH entries to ~/.profile, ~/.bashrc, and ~/.zshrc (if it exists).
# Writing to ~/.profile lets login/non-interactive shells (cron, ssh CMD, IDE tasks) pick up
# PATH too — Ubuntu's default bashrc bails early for non-interactive shells.
link_shell_rc_paths() {
  local marker="# >>> dotfiles: PATH additions >>>"
  local endmarker="# <<< dotfiles: PATH additions <<<"
  # NOTE: emit the block with a heredoc *at the point of use* rather than
  # capturing it via block="$(cat <<'EOF' ... EOF)". macOS ships bash 3.2, whose
  # parser scans for the closing paren of a command substitution through the
  # heredoc body — the ")" in `*"...:"*)` ends the substitution early and the
  # remainder gets expanded as live shell text, corrupting the rc files.
  _emit_path_block() {
    cat <<'EOF'
# go: upstream install lives in /usr/local/go; user tools land in $GOPATH/bin
if [ -d /usr/local/go/bin ]; then
  case ":$PATH:" in *":/usr/local/go/bin:"*) ;; *) export PATH="$PATH:/usr/local/go/bin" ;; esac
fi
if [ -d "$HOME/go/bin" ]; then
  case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$PATH:$HOME/go/bin" ;; esac
fi
# pipx: user-scoped Python CLIs (tldr, etc.) live in ~/.local/bin
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$PATH:$HOME/.local/bin" ;; esac
fi
EOF
  }

  local rc
  # ~/.profile is a login-shell rc; both bash and sh read it, and it runs before
  # bashrc's interactive-only guard. Ensures PATH additions work for
  # non-interactive shells too (cron, ssh with command, IDE tasks).
  for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    # For .profile / .bashrc: touch into existence. For .zshrc: only append when it exists.
    case "$rc" in
      "$HOME/.zshrc") [[ -f "$rc" ]] || continue ;;
      *)              touch "$rc" ;;
    esac

    if grep -Fq "$marker" "$rc"; then
      log "✓ $rc already contains PATH block"
      continue
    fi
    {
      printf '\n%s\n' "$marker"
      _emit_path_block
      printf '%s\n' "$endmarker"
    } >> "$rc"
    log "✓ appended PATH block to $rc"
  done

  unset -f _emit_path_block
}

# Idempotent: adds fzf key-bindings + fuzzy-completion init to per-shell rc files.
# Each shell needs a different invocation:
#   bash:  eval "$(fzf --bash)"
#   zsh:   source <(fzf --zsh)
#   fish:  fzf --fish | source
link_fzf_init() {
  local marker="# >>> dotfiles: fzf init >>>"
  local endmarker="# <<< dotfiles: fzf init <<<"

  _append_fzf_block() {
    local rc="$1" body="$2" only_if_exists="${3:-0}"
    if [[ "$only_if_exists" == "1" && ! -f "$rc" ]]; then return; fi
    mkdir -p "$(dirname "$rc")"
    touch "$rc"
    if grep -Fq "$marker" "$rc"; then
      log "✓ $rc already contains fzf init block"
      return
    fi
    {
      printf '\n%s\n' "$marker"
      printf '# Set up fzf key bindings and fuzzy completion\n'
      printf '%s\n' "$body"
      printf '%s\n' "$endmarker"
    } >> "$rc"
    log "✓ appended fzf init block to $rc"
  }

  _append_fzf_block "$HOME/.bashrc"                       'command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"'
  _append_fzf_block "$HOME/.zshrc"                        'command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)' 1
  # fish: use `type -q` rather than `command -v ... >/dev/null 2>&1`; it is the
  # idiomatic test and avoids POSIX redirection syntax fish only gained in 3.0.
  _append_fzf_block "$HOME/.config/fish/config.fish"      'type -q fzf; and fzf --fish | source' 1

  unset -f _append_fzf_block
}

# ---------- Step 4: tmux plugins ----------
step_tmux_plugins() {
  local tpm_dir="$HOME/.tmux/plugins/tpm"
  if [[ ! -d "$tpm_dir" ]]; then
    log "cloning TPM into ${tpm_dir}…"
    command -v git >/dev/null 2>&1 || die "git is required to install TPM"
    git clone --depth=1 https://github.com/tmux-plugins/tpm "$tpm_dir"
  else
    log "✓ TPM already present at $tpm_dir"
  fi

  # TPM's install_plugins needs a running tmux server; start a throwaway one if needed.
  local install_script="$tpm_dir/bin/install_plugins"
  [[ -x "$install_script" ]] || die "TPM install script not found or not executable: $install_script"

  log "installing tmux plugins via TPM…"
  if tmux info >/dev/null 2>&1; then
    "$install_script"
  else
    tmux new-session -d -s __dotfiles_bootstrap__ "sleep 30" 2>/dev/null || true
    "$install_script" || true
    tmux kill-session -t __dotfiles_bootstrap__ 2>/dev/null || true
  fi
  log "✓ tmux plugins installed"
}

# ---------- Entry point ----------
main() {
  local cmd="${1:-all}"
  case "$cmd" in
    all)          step_timezone; step_tools; step_optional; step_link; step_tmux_plugins ;;
    timezone)     step_timezone ;;
    tools)        step_tools ;;
    optional)     step_optional ;;
    link)         step_link ;;
    tmux-plugins) step_tmux_plugins ;;
    -h|--help|help)
      sed -n '2,11p' "$0"
      ;;
    *) die "unknown command: $cmd (see --help)" ;;
  esac
  log "done."
}

main "$@"
