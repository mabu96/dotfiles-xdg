# Interactive shell configuration — sourced by zsh for interactive sessions.
# Lives in $ZDOTDIR (~/dotfiles/config/zsh) so it's version-controlled.

# ── Homebrew ──────────────────────────────────────────────────────────────────
# brew shellenv sets PATH, MANPATH, INFOPATH, etc. The guard avoids double-
# sourcing when the shell is both login + interactive (.zprofile already ran it).
if [[ -z $HOMEBREW_PREFIX ]] && [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ── Completions ───────────────────────────────────────────────────────────────
# OpenClaw CLI completions (installed by openclaw setup).
[[ -f "$HOME/.openclaw/completions/openclaw.zsh" ]] && source "$HOME/.openclaw/completions/openclaw.zsh"
