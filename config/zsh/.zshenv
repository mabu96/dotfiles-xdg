# Managed by bootstrap.zsh — do not edit by hand.
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
