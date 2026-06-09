#!/usr/bin/env zsh
# bootstrap.zsh — initialize an XDG-organized dotfiles layout on a fresh
# macOS account. Idempotent: safe to run repeatedly.
#
# What it does:
#   1. Verifies git is on PATH.
#   2. Creates the skeleton directories under ~/dotfiles.
#   3. Initializes ~/dotfiles as a git repo (if not already one).
#   4. Writes ~/.zshenv with XDG and per-tool relocation env vars.
#   5. Symlinks any entries in HOME_LINKS from $HOME into the repo's home/.
#
# What it does NOT do:
#   - Touch ~/.ssh (explicitly refused).
#   - Clone any existing dotfiles repo.
#   - Install Homebrew or any tool.
#   - Configure MCP servers (each AI agent owns its own MCP config).

setopt err_exit no_unset pipe_fail

# ─── config ──────────────────────────────────────────────────────────────────
REPO_DIR="$HOME/dotfiles"

# Directories created under $REPO_DIR. Extend as new tools land.
SKELETON=(
  config/zsh
  config/git
  config/gnupg
  config/readline
  config/wget
  config/claude
  config/codex
  config/gemini
  config/opencode
  config/aider
  config/hermes
  data
  data/npm
  state/less
  state/aider
  state/node
  cache
  cache/npm
  home
  home/.local/bin
)

# $HOME path → repo-relative path. Source must exist in the repo to symlink.
# Empty by default. Add entries here as you commit files into home/.
typeset -A HOME_LINKS
HOME_LINKS=(
  # Active relocations (script symlinks each on every run once src exists).
  .ollama           home/.ollama          # Ollama: hardcodes $HOME/.ollama, no env var.
  .local            home/.local           # Anthropic claude installer, pip --user, etc. put binaries in ~/.local/bin.

  # Apps that hardcode ~/.config/<app> (don't respect $XDG_CONFIG_HOME).
  .config/linearmouse   config/linearmouse
  .config/raycast       config/raycast
  .config/zed           config/zed

  # Examples (uncomment + commit the source file/dir into the repo before re-running):
  # .bashrc           home/.bashrc
  # .bash_profile     home/.bash_profile
  # .vimrc            home/.vimrc
  # .lesskey          home/.lesskey
  #
  # Tools with no env-var support — relocate via symlink:
  # .gemini           home/.gemini          # directory; create home/.gemini/ in repo first
  # .aider.conf.yml   home/.aider.conf.yml  # file
)

# ─── helpers ─────────────────────────────────────────────────────────────────
log()  { print -r -- "  $*"; }
ok()   { print -r -- "✓ $*"; }
warn() { print -r -- "! $*" >&2; }
step() { print -- "\n── $* ──"; }

# Returns a non-colliding backup path for $1 (echoes the path).
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
ok "git present"

# ─── 2. skeleton dirs ────────────────────────────────────────────────────────
step "skeleton"
for rel in "${SKELETON[@]}"; do
  dir="$REPO_DIR/$rel"
  if [[ -d $dir ]]; then
    log "exists: $rel"
  else
    mkdir -p $dir
    ok "created: $rel"
  fi
done

# ─── 3. git init ─────────────────────────────────────────────────────────────
step "git init"
if [[ -d $REPO_DIR/.git ]]; then
  ok "already a git repo"
else
  git -C $REPO_DIR init -q
  ok "initialized"
fi

# ─── 4. .zshenv ──────────────────────────────────────────────────────────────
step ".zshenv"
ZSHENV_CONTENT='# Bootstrap-managed. Edit with care; bootstrap.zsh rewrites this file
# if it differs from the canonical content.

# XDG basics
export XDG_CONFIG_HOME="$HOME/dotfiles/config"
export XDG_DATA_HOME="$HOME/dotfiles/data"
export XDG_STATE_HOME="$HOME/dotfiles/state"
export XDG_CACHE_HOME="$HOME/dotfiles/cache"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"

# Tools with env vars but no XDG-respect by default
export GNUPGHOME="$XDG_CONFIG_HOME/gnupg"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export INPUTRC="$XDG_CONFIG_HOME/readline/inputrc"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"

# git: point the "global" config at the XDG location so `git config --global …`
# (and helpers like `gh auth setup-git`) write into the managed tree instead of
# ~/.gitconfig. Git itself reads BOTH ~/.gitconfig and $XDG_CONFIG_HOME/git/config
# automatically, so this only affects writes.
export GIT_CONFIG_GLOBAL="$XDG_CONFIG_HOME/git/config"

# AI CLI agents — env vars verified against upstream docs (see README).
export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"
export CODEX_HOME="$XDG_CONFIG_HOME/codex"
export OPENCODE_CONFIG_DIR="$XDG_CONFIG_HOME/opencode"
export HERMES_HOME="$XDG_CONFIG_HOME/hermes"
export AIDER_CHAT_HISTORY_FILE="$XDG_STATE_HOME/aider/chat.history.md"
export AIDER_INPUT_HISTORY_FILE="$XDG_STATE_HOME/aider/input.history"

# Gemini CLI has NO env var to relocate ~/.gemini (issue #2815 unimplemented
# as of 2026-06). Relocate via symlink instead — see HOME_LINKS in bootstrap.zsh.

# Aider has no env var for its config FILE (~/.aider.conf.yml). Relocate via
# symlink (HOME_LINKS) or use `alias aider="aider --config ..."`.

# npm: keep cache + global install prefix inside the dotfiles tree so a fresh
# `npm install -g ...` doesn'\''t scatter ~/.npm and ~/.local. The prefix is the
# install root: binaries land in $NPM_CONFIG_PREFIX/bin, libs in /lib.
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export NPM_CONFIG_PREFIX="$XDG_DATA_HOME/npm"

# Native installers (Claude Code'\''s `curl ... | bash`, pip --user, cargo, etc.)
# put binaries in $HOME/.local/bin. Bootstrap symlinks ~/.local to home/.local
# inside the repo (see HOME_LINKS), so those binaries effectively live in the
# managed tree. Put it on PATH ahead of the npm prefix.
export PATH="$HOME/.local/bin:$NPM_CONFIG_PREFIX/bin:$PATH"

# Dedupe PATH. zsh ties $path (array) to $PATH (string); typeset -U makes
# the array unique-only. Without this, every `exec zsh` re-prepends the
# same entries and PATH grows unbounded across nested shells.
typeset -U path PATH

# node REPL history (default ~/.node_repl_history).
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/repl_history"
'

target="$HOME/.zshenv"
tmp=$(mktemp)
print -rn -- "$ZSHENV_CONTENT" > "$tmp"

if [[ -f $target && ! -L $target ]] && cmp -s "$target" "$tmp"; then
  ok ".zshenv already correct"
  rm -f "$tmp"
else
  if [[ -e $target ]]; then
    bk=$(backup_path $target)
    mv $target $bk
    log "backed up old .zshenv → $bk"
  fi
  mv "$tmp" "$target"
  ok "wrote .zshenv"
fi

# ─── 4b. ZDOTDIR shim ────────────────────────────────────────────────────────
# zsh's startup rules: when $ZDOTDIR is set in the env, zsh reads
# $ZDOTDIR/.zshenv instead of $HOME/.zshenv. Without this shim, anything
# `exec zsh` (or any new shell spawned from a shell that already exported
# ZDOTDIR) skips ~/.zshenv entirely — env vars added there don't reach the
# new shell until the user logs out and back in. Make $ZDOTDIR/.zshenv a
# symlink to $HOME/.zshenv so both startup paths resolve to the same file.
step "ZDOTDIR shim"
shim="$REPO_DIR/config/zsh/.zshenv"
if [[ -L $shim && "$(readlink $shim)" == "$target" ]]; then
  ok "shim already present"
else
  if [[ -L $shim ]]; then
    rm $shim
    log "removed stale shim symlink"
  elif [[ -e $shim ]]; then
    bk=$(backup_path $shim)
    mv $shim $bk
    log "backed up existing $shim → $bk"
  fi
  ln -s $target $shim
  ok "linked: $shim → $target"
fi

# ─── 5. symlinks for non-XDG tools ───────────────────────────────────────────
step "symlinks"

# Merge auto-discovered entries from home_links.conf (managed by dotfiles-guard).
AUTO_LINKS_CONF="$REPO_DIR/home_links.conf"
if [[ -f "$AUTO_LINKS_CONF" ]]; then
  while IFS=$'\t' read -r rel repo_rel; do
    [[ "$rel" == \#* || -z "$rel" ]] && continue
    # Reject malformed entries: empty target, absolute paths, path traversal.
    if [[ -z "$repo_rel" || "$rel" == /* || "$repo_rel" == /* || "$rel" == *'..'* || "$repo_rel" == *'..'* ]]; then
      warn "skip invalid home_links.conf entry: rel='$rel' repo_rel='$repo_rel'"
      continue
    fi
    HOME_LINKS[$rel]="$repo_rel"
  done < "$AUTO_LINKS_CONF"
fi

if (( ${#HOME_LINKS} == 0 )); then
  log "(none configured — add entries to HOME_LINKS as you populate home/)"
else
  for rel in ${(k)HOME_LINKS}; do
    src="$REPO_DIR/${HOME_LINKS[$rel]}"
    dst="$HOME/$rel"

    # ~/.ssh is off-limits no matter what the map says.
    if [[ $dst == $HOME/.ssh* ]]; then
      warn "refusing to touch $dst (~/.ssh is off-limits)"
      continue
    fi

    if [[ ! -e $src ]]; then
      warn "skip $rel — source missing in repo: $src"
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

    mkdir -p "${dst:h}"   # ensure parent exists (e.g. ~/.config/ for .config/linearmouse)
    ln -s $src $dst
    ok "linked: $rel → $src"
  done
fi

step "done"
