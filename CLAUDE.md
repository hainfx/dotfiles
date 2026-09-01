# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A personal dotfiles repo with a single-file installer. It targets three platform families from one codebase: Debian/Ubuntu (`apt-get`), RHEL/CentOS/Fedora/Rocky/Alma/TencentOS (`dnf`/`yum` + EPEL), and macOS (Homebrew). Servers and containers are first-class targets, so nothing may assume an interactive terminal, a GUI, or a pre-existing `$HOME` rc file.

## Commands

`Makefile` is a thin wrapper over `install.sh` — every target except `clean` just calls `./install.sh <step>`. There is no build, lint, or test suite.

```
make install        # full flow: timezone + tools + optional + link + tmux-plugins
make timezone       # set system timezone to Asia/Singapore
make tools          # required tools only (vim tmux fzf curl)
make optional       # optional tools (git make docker python3 unzip) + upstream Go/bun + nvm with node 24 + tldr via pipx
make link           # symlinks + rc-file blocks; the target to run after editing dotfiles
make tmux-plugins   # clone TPM and install tmux plugins
make clean          # remove symlinks, TPM, and all rc-file blocks
./install.sh <step> # same steps, callable directly
```

To verify a change, run the individual step (`./install.sh link`) rather than the full flow — every step is idempotent and safe to re-run. `make clean && make link` exercises the write/remove round-trip.

## Architecture

**`install.sh` is the whole program** (~830 lines, `set -euo pipefail`). It is organized as numbered steps dispatched from `main()`: `step_timezone`, `step_tools`, `step_optional` (which fans out to `step_tldr`, `step_go`, `step_nvm`, `step_node`, `step_npm`, `step_bun`), `step_link`, `step_tmux_plugins`. Platform differences are funneled through three helpers rather than scattered `if [[ $(uname) ]]` checks:

- `detect_os()` → `debian` | `rhel` | `macos`
- `pkg_name_for(os, tool)` → the per-distro package name (e.g. `docker` → `docker.io` on Debian; `python3` → the highest available `python3.X` on RHEL via `rhel_python_pkg`)
- `install_pkg(os, pkg)` → the actual package-manager invocation

Adding a tool means appending to `REQUIRED_TOOLS` or `OPTIONAL_TOOLS` and, only if the package name differs somewhere, adding a `pkg_name_for` case. Required-tool failures abort; optional ones warn and continue. Go, node, bun and `tldr` bypass the package manager entirely and so live in their own steps: Go from an upstream tarball into `/usr/local/go`; node from **nvm** (`NVM_VERSION` pins the installer tag, `NODE_VERSION=24` the series, and `nvm alias default` makes it what new shells pick up); bun from its GitHub `releases/latest/download/` zip into `~/.bun` (hence `unzip` in `OPTIONAL_TOOLS`, and the `-baseline` asset on x86-64 CPUs without AVX2); `tldr` from pipx.

Two details there are load-bearing. **Every nvm call goes through `with_nvm`**, which sources `nvm.sh` in a subshell with `set +u +e` — nvm is a shell function, not a binary, and `nvm.sh` reads unset variables, so it cannot be sourced under the script's `set -euo pipefail`. And **`step_npm` asks nvm before it asks `$PATH`**: npm ships inside the node nvm just installed, but that node is not on `$PATH` until a *new* shell reads the nvm init block, so a PATH-only check would declare npm missing and install a redundant distro `npm` (which drags in the distro's old nodejs). `npm` stays out of `OPTIONAL_TOOLS` for the same reason — that list is installed before `step_node` runs.

**Marker-block editing of `$HOME` rc files** is the core idempotency mechanism. `step_link` never copies files — it symlinks `tmux/.tmux.conf` and `vim/.vimrc` into `$HOME`, and appends *sourcing* lines for `bash/.workrc` / `zsh/.workrc`, so repo edits take effect without re-running the installer. Three separate block writers each own a marker pair:

| Writer | Marker | Targets |
|---|---|---|
| `link_workrc` | `# >>> dotfiles: source <shell>/.workrc >>>` | `~/.bashrc`, `~/.zshrc` |
| `link_shell_rc_paths` | `# >>> dotfiles: PATH additions >>>` | `~/.profile`, `~/.bashrc`, `~/.zshrc` |
| `link_nvm_init` | `# >>> dotfiles: nvm init >>>` | `~/.bashrc`, `~/.zshrc` |
| `link_fzf_init` | `# >>> dotfiles: fzf init >>>` | `~/.bashrc`, `~/.zshrc`, `~/.config/fish/config.fish` |

The PATH block covers `/usr/local/go/bin`, `$HOME/go/bin`, `$HOME/.bun/bin`, `$HOME/.local/bin`. node is absent from it on purpose: nvm has to be *sourced*, so it gets its own block, which goes only to `~/.bashrc`/`~/.zshrc` (`nvm.sh` is not POSIX-sh safe, so `~/.profile` is excluded and cron / `ssh host cmd` do not see node) and emits the `bash_completion` line for bash only (zsh has no `complete` without `bashcompinit`). `install_nvm` passes `PROFILE=/dev/null` so nvm's own installer does not append a second, *unmarked* copy of that block that `make clean` could never remove.

Because every writer skips a file that already has its marker, **changing a block's contents does not update rc files that already contain it** — `make clean && make link` is the upgrade path.

Every writer greps for its marker before appending. `make clean` deletes by the same marker pairs with `sed`, so **any new block must add matching `>>>`/`<<<` markers to both the writer and the `clean` target** or it becomes unremovable. `~/.profile` gets the PATH block specifically because Ubuntu's default `.bashrc` returns early for non-interactive shells (cron, `ssh host cmd`, IDE tasks).

**Shell rc pairing.** `bash/.workrc` and `zsh/.workrc` are hand-maintained ports of each other (bash `PS1` with `\u`/`\H`/`\w`/`\[…\]` vs zsh `PROMPT` with `%n`/`%M`/`%~`/`%{…%}`). A change to one should normally be mirrored in the other. `~/.zshrc` is created on demand when zsh is installed; fish is only ever appended to if its config already exists.

## Constraints when editing `install.sh`

These are load-bearing and already caused bugs; the file carries comments explaining each:

- **macOS ships bash 3.2.** No associative arrays, no `${var^^}`. Critically, its parser scans through a heredoc body for the closing paren of a command substitution — so never write `block="$(cat <<'EOF' … EOF)"` when the body contains `)`. Emit heredocs at the point of use (see `_emit_path_block`).
- **`sudo_cmd` returns non-zero instead of dying**, because it runs inside `$(...)` where `exit` would only kill the subshell. Every caller must use `sudo="$(sudo_cmd)" || return 1`.
- **Use `$sudo env VAR=val cmd`, not `VAR=val $sudo cmd`** — bash does not treat an assignment as a prefix when the first token expands to empty (the root case).
- **No `trap ... RETURN` for cleanup.** RETURN traps are not function-local; one armed on an early-return path re-fires on later returns. `install_go_from_upstream` cleans up explicitly on each path instead.
- **`tool_works` actually executes the tool**, because `command -v` cannot see a dead shebang — the common case is a pipx venv orphaned by a `$HOME` move. It special-cases `tmux -V`, `go version` and `unzip -v`, none of which accept `--version`.
- Package-listing subshells (`rhel_python_pkg`) must stay unprivileged, or a sudo password prompt gets swallowed inside the command substitution.
