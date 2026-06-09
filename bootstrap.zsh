#!/usr/bin/env zsh
# bootstrap.zsh — idempotent setup for the shared XDG dotfiles layout.
# Safe to run from any account that is a member of the admin group.
#
# What it does:
#   1. Verifies git is on PATH and the shared dir exists.
#   2. Migration: converts old ~/.local symlink to real per-user dirs (once).
#   3. Ensures shared skeleton dirs exist under SHARED_DIR.
#   4. Creates per-user skeleton dirs under $HOME.
#   5. Git: adds safe.directory + ensures core.sharedRepository=group.
#      First account runs git init; subsequent accounts only onboard.
#   6. Writes canonical .zshenv to SHARED_DIR/config/zsh/.zshenv and
#      symlinks $HOME/.zshenv → it. Both $HOME/.zshenv and $ZDOTDIR/.zshenv
#      resolve to the same shared file, so no separate ZDOTDIR shim needed.
#   7. Symlinks HOME_LINKS entries from $HOME into SHARED_DIR.
#   8. Installs per-user LaunchAgents (bootstrap agent + guard agent).
#
# What it does NOT do:
#   - Touch ~/.ssh.
#   - Clone any remote repo, push, rewrite history, or move the repo.
#   - Install Homebrew or any tool.

setopt err_exit no_unset pipe_fail

# ─── config ──────────────────────────────────────────────────────────────────
SHARED_DIR="${DOTFILES_SHARED:-/Users/Shared/dotfiles}"

# Dirs created once under SHARED_DIR (version-controlled, shared across accounts).
SHARED_SKELETON=(
  config/zsh
  config/git
  config/readline
  config/wget
  config/aider
  config/gh
  config/launchd
  bin
  home
  home/.local/bin
)

# Dirs created per-account under $HOME (never shared, never committed).
HOME_SKELETON=(
  .local/bin
  .local/share/npm
  .local/state/zsh
  .local/state/less
  .local/state/aider
  .local/state/node
  .local/state/dotfiles
  .local/state/guard
  .local/state/guard/quarantine
  .cache/npm
  .config/claude
  .config/codex
  .config/gemini
  .config/opencode
  .config/hermes
  .config/gnupg
  Library/LaunchAgents
)

# $HOME path → SHARED_DIR-relative path.
# Source must exist in SHARED_DIR to symlink. ~/.ssh is always refused.
typeset -A HOME_LINKS
HOME_LINKS=(
  # Ollama hardcodes $HOME/.ollama with no env var; share models across accounts
  # (same person, same Mac). Identity files are machine-level, not account-level.
  .ollama           home/.ollama

  # Apps that hardcode ~/.config/<app> (don't respect $XDG_CONFIG_HOME).
  .config/linearmouse   config/linearmouse
  .config/raycast       config/raycast
  .config/zed           config/zed

  # Examples (uncomment + commit source into SHARED_DIR before re-running):
  # .gemini           home/.gemini          # Gemini CLI: no env var, symlink only
  # .aider.conf.yml   home/.aider.conf.yml  # Aider config: no env var, symlink only
)

# Canonical .zshenv content. Uses $HOME (expands per-account at runtime) for
# per-user paths; uses the hardcoded /Users/Shared/dotfiles constant for shared.
# This file is tracked in git at config/zsh/.zshenv; $HOME/.zshenv symlinks to it.
ZSHENV_CONTENT='# Managed by bootstrap.zsh — do not edit by hand.
# $HOME/.zshenv is a symlink to this file (SHARED_DIR/config/zsh/.zshenv).
# Both $HOME/.zshenv and $ZDOTDIR/.zshenv resolve here; edit the shared file.

export DOTFILES_SHARED="/Users/Shared/dotfiles"

# XDG: shared config, per-user data/state/cache.
export XDG_CONFIG_HOME="$DOTFILES_SHARED/config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export HISTFILE="$XDG_STATE_HOME/zsh/history"

# Shared tools — portable config, no lock contention between accounts.
export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"
export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"

# Per-user tool dirs — avoid lock/session collisions between accounts.
export CLAUDE_CONFIG_DIR="$HOME/.config/claude"
export CODEX_HOME="$HOME/.config/codex"
export OPENCODE_CONFIG_DIR="$HOME/.config/opencode"
export HERMES_HOME="$HOME/.config/hermes"
export GNUPGHOME="$HOME/.config/gnupg"

# Per-user state files.
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export AIDER_CHAT_HISTORY_FILE="$XDG_STATE_HOME/aider/chat.history.md"
export AIDER_INPUT_HISTORY_FILE="$XDG_STATE_HOME/aider/input.history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/repl_history"

# Gemini CLI has NO env var to relocate ~/.gemini (issue #2815 unimplemented
# as of 2026-06). Relocate via symlink — see HOME_LINKS in bootstrap.zsh.

# Aider has no env var for its config file (~/.aider.conf.yml). Relocate via
# symlink (HOME_LINKS) or alias aider="aider --config ...".

# npm: per-user cache + per-user global install prefix.
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export NPM_CONFIG_PREFIX="$XDG_DATA_HOME/npm"

# PATH: per-user ~/.local/bin first, then npm prefix bin.
export PATH="$HOME/.local/bin:$NPM_CONFIG_PREFIX/bin:$PATH"

# Dedupe PATH — zsh ties $path (array) to $PATH (string).
# Without this, every `exec zsh` re-prepends and PATH grows unbounded.
typeset -U path PATH
'

# ─── helpers ─────────────────────────────────────────────────────────────────
log()  { print -r -- "  $*"; }
ok()   { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }
step() { print -- "\n── $* ──"; }

backup_path() {
  local base="$1.bak"
  if [[ -e $base ]]; then
    base="$1.bak.$(date +%Y%m%d%H%M%S)"
  fi
  print -r -- $base
}

# ─── 1. pre-flight ───────────────────────────────────────────────────────────
step "pre-flight"
command -v git >/dev/null || { warn "git not found on PATH"; exit 1; }
[[ -d $SHARED_DIR ]] || {
  warn "$SHARED_DIR does not exist."
  warn "Run the one-time admin setup first:"
  warn "  sudo mkdir -p /Users/Shared/dotfiles"
  warn "  sudo mv ~/dotfiles /Users/Shared/dotfiles  # or clone there"
  warn "  sudo chgrp -R admin /Users/Shared/dotfiles"
  warn "  sudo chmod -R g+rwX /Users/Shared/dotfiles"
  warn "  sudo find /Users/Shared/dotfiles -type d -exec chmod g+s {} +"
  exit 1
}
ok "git present, $SHARED_DIR exists"

# ─── 2. migration: old ~/.local symlink ──────────────────────────────────────
step "migration check"
if [[ -L "$HOME/.local" ]]; then
  old_target="$(readlink "$HOME/.local")"
  warn "~/.local is a symlink → $old_target (old per-repo layout)"
  warn "Removing symlink — binaries in $old_target/bin need reinstalling."
  rm "$HOME/.local"
  log "removed ~/.local symlink; per-user dirs will be created below"
else
  ok "~/.local is a real dir or absent (no migration needed)"
fi

# ─── 3. shared skeleton ──────────────────────────────────────────────────────
step "shared skeleton"
for rel in "${SHARED_SKELETON[@]}"; do
  dir="$SHARED_DIR/$rel"
  if [[ -d $dir ]]; then
    log "exists: $rel"
  else
    mkdir -p $dir
    ok "created: $rel"
  fi
done

# ─── 4. per-user skeleton ────────────────────────────────────────────────────
step "per-user skeleton"
for rel in "${HOME_SKELETON[@]}"; do
  dir="$HOME/$rel"
  if [[ -d $dir ]]; then
    log "exists: ~/$rel"
  else
    mkdir -p $dir
    ok "created: ~/$rel"
  fi
done

# ─── 5. git ──────────────────────────────────────────────────────────────────
step "git"

# Add safe.directory before any git operations on the shared repo.
# Use the shared git config (GIT_CONFIG_GLOBAL) explicitly — consistent
# whether .zshenv has been loaded yet or not on this account.
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-$SHARED_DIR/config/git/config}"
git config --global --get-all safe.directory 2>/dev/null | \
  grep -qxF "$SHARED_DIR" || \
  git config --global --add safe.directory "$SHARED_DIR"
ok "safe.directory set in $GIT_CONFIG_GLOBAL"

if [[ -d $SHARED_DIR/.git ]]; then
  ok "shared repo already initialized"
  git -C "$SHARED_DIR" config core.sharedRepository=group
else
  git -C "$SHARED_DIR" init -q
  git -C "$SHARED_DIR" config core.sharedRepository=group
  ok "initialized shared repo at $SHARED_DIR"
fi

# ─── 6. .zshenv ──────────────────────────────────────────────────────────────
step ".zshenv"
shared_zshenv="$SHARED_DIR/config/zsh/.zshenv"
tmp=$(mktemp)
print -rn -- "$ZSHENV_CONTENT" > "$tmp"

if [[ -f $shared_zshenv && ! -L $shared_zshenv ]] && cmp -s "$shared_zshenv" "$tmp"; then
  ok "shared .zshenv already correct"
  rm -f "$tmp"
else
  if [[ -e $shared_zshenv || -L $shared_zshenv ]]; then
    bk=$(backup_path "$shared_zshenv")
    mv "$shared_zshenv" "$bk"
    log "backed up old shared .zshenv → $bk"
  fi
  mv "$tmp" "$shared_zshenv"
  ok "wrote $shared_zshenv"
fi

home_zshenv="$HOME/.zshenv"
if [[ -L $home_zshenv && "$(readlink $home_zshenv)" == "$shared_zshenv" ]]; then
  ok "$HOME/.zshenv symlink correct"
else
  if [[ -e $home_zshenv || -L $home_zshenv ]]; then
    bk=$(backup_path "$home_zshenv")
    mv "$home_zshenv" "$bk"
    log "backed up $HOME/.zshenv → $bk"
  fi
  ln -s "$shared_zshenv" "$home_zshenv"
  ok "linked: $HOME/.zshenv → $shared_zshenv"
fi

# ─── 7. symlinks for non-XDG tools ───────────────────────────────────────────
step "symlinks"

AUTO_LINKS_CONF="$SHARED_DIR/home_links.conf"
if [[ -f "$AUTO_LINKS_CONF" ]]; then
  while IFS=$'\t' read -r rel repo_rel; do
    [[ "$rel" == \#* || -z "$rel" ]] && continue
    if [[ -z "$repo_rel" || "$rel" == /* || "$repo_rel" == /* || \
          "$rel" == *'..'* || "$repo_rel" == *'..'* ]]; then
      warn "skip invalid home_links.conf entry: rel='$rel' repo_rel='$repo_rel'"
      continue
    fi
    HOME_LINKS[$rel]="$repo_rel"
  done < "$AUTO_LINKS_CONF"
fi

if (( ${#HOME_LINKS} == 0 )); then
  log "(none configured — add entries to HOME_LINKS or home_links.conf)"
else
  for rel in ${(k)HOME_LINKS}; do
    src="$SHARED_DIR/${HOME_LINKS[$rel]}"
    dst="$HOME/$rel"

    if [[ $dst == $HOME/.ssh* ]]; then
      warn "refusing to touch $dst (~/.ssh is off-limits)"
      continue
    fi

    if [[ ! -e $src ]]; then
      warn "skip $rel — source missing in shared repo: $src"
      continue
    fi

    if [[ -L $dst && "$(readlink $dst)" == "$src" ]]; then
      ok "ok: $rel"
      continue
    fi

    if [[ -L $dst ]]; then
      rm $dst
      log "removed stale symlink: $dst"
    elif [[ -e $dst ]]; then
      bk=$(backup_path $dst)
      mv $dst $bk
      log "backed up $rel → $bk"
    fi

    mkdir -p "${dst:h}"
    ln -s $src $dst
    ok "linked: $rel → $src"
  done
fi

# ─── 8. LaunchAgents ─────────────────────────────────────────────────────────
step "LaunchAgents"

install_launchagent() {
  local label="$1" plist_src="$2"
  local plist_dst="$HOME/Library/LaunchAgents/${label}.plist"

  if [[ ! -f $plist_src ]]; then
    warn "plist source not found: $plist_src — skipping $label"
    return 0
  fi

  if [[ -f $plist_dst ]] && cmp -s "$plist_src" "$plist_dst"; then
    ok "$label: plist up to date"
  else
    if [[ -e $plist_dst ]]; then
      bk=$(backup_path "$plist_dst")
      mv "$plist_dst" "$bk"
      log "backed up old $label plist → $bk"
    fi
    cp "$plist_src" "$plist_dst"
    chmod 644 "$plist_dst"
    ok "$label: installed plist"
  fi

  if launchctl list "$label" >/dev/null 2>&1; then
    ok "$label: already loaded"
  else
    launchctl bootstrap "gui/$(id -u)" "$plist_dst" 2>/dev/null && \
      ok "$label: loaded" || \
      warn "$label: load failed — run: launchctl bootstrap gui/\$(id -u) $plist_dst"
  fi
}

install_launchagent "com.dotfiles.bootstrap" \
  "$SHARED_DIR/config/launchd/com.dotfiles.bootstrap.plist"
install_launchagent "com.dotfiles.guard" \
  "$SHARED_DIR/config/launchd/com.dotfiles.guard.plist"

step "done"
