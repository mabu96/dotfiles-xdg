# dotfiles

XDG-organized dotfiles for a shared macOS setup. One repo at
`/Users/Shared/dotfiles` serves all accounts on this Mac. `bootstrap.zsh`
is idempotent and safe to re-run on any account.

## Architecture

| Tier | Location | What | Shared? |
|------|----------|------|---------|
| Version-controlled config | `/Users/Shared/dotfiles/config` (`XDG_CONFIG_HOME`) | zsh rc, git config, readline, wget, skills, `bin/`, `Brewfile` | **Shared** — one git repo |
| Per-user data | `$HOME/.local/share` (`XDG_DATA_HOME`) | npm globals, uv pythons | Per-user |
| Per-user state | `$HOME/.local/state` (`XDG_STATE_HOME`) | histories, guard logs, aider/node state | Per-user |
| Per-user cache | `$HOME/.cache` (`XDG_CACHE_HOME`) | npm/uv/gh caches | Per-user |
| Per-user tool dirs | `$HOME/.config/<tool>` | claude, codex, hermes, gnupg | Per-user (avoid lock collisions) |

Key principle: **gitignored per-tool runtime stays per-user** even though it
nominally sits under "config." The portable, version-controlled config is what's
shared. Lock files, session tokens, and credentials must never be shared between
accounts even when they belong to the same person.

## Layout

```
/Users/Shared/dotfiles/
├── README.md
├── bootstrap.zsh            # the bootstrap script (idempotent, run on any account)
├── .gitignore
├── .git/
├── Brewfile
├── config/                  # $XDG_CONFIG_HOME — shared across accounts
│   ├── zsh/
│   │   ├── .zshenv          # canonical env vars (tracked); $HOME/.zshenv symlinks here
│   │   ├── .zprofile        # login shell (brew shellenv, etc.)
│   │   └── .zshrc           # interactive shell
│   ├── git/                 # $GIT_CONFIG_GLOBAL
│   ├── readline/            # $INPUTRC
│   ├── wget/                # $WGETRC
│   ├── aider/               # aider config (no state)
│   ├── gh/                  # gh config.yml (hosts.yml gitignored — has tokens)
│   ├── launchd/             # tracked LaunchAgent plists (shared, no per-user paths)
│   │   ├── com.dotfiles.bootstrap.plist
│   │   └── com.dotfiles.guard.plist
│   ├── linearmouse/         # symlink target for ~/.config/linearmouse
│   ├── raycast/             # symlink target for ~/.config/raycast
│   └── zed/                 # symlink target for ~/.config/zed
├── bin/
│   ├── dotfiles-guard              # guard script (reads SHARED_DIR, writes per-user state)
│   ├── dotfiles-guard-agent        # LaunchAgent wrapper (creates log dir, execs guard)
│   └── dotfiles-bootstrap-agent   # LaunchAgent wrapper (creates log dir, execs bootstrap)
└── home/                    # files that must live in $HOME
    └── .ollama/             # symlink target for ~/.ollama (shared Ollama models)
```

Per-user dirs (`~/.local/share`, `~/.local/state`, `~/.cache`, `~/.config/<tool>`)
are created by bootstrap on each account. They never appear in this repo.

## Onboarding a fresh account

### First account (establishes the shared repo)

```sh
# One-time admin setup (run once, as any admin account):
sudo mkdir -p /Users/Shared/dotfiles
sudo mv ~/dotfiles /Users/Shared/dotfiles     # or git clone there
sudo chgrp -R admin /Users/Shared/dotfiles
sudo chmod -R g+rwX /Users/Shared/dotfiles
sudo find /Users/Shared/dotfiles -type d -exec chmod g+s {} +

# Then bootstrap the account:
zsh /Users/Shared/dotfiles/bootstrap.zsh
exec zsh                                      # pick up new env vars
print $XDG_CONFIG_HOME                        # → /Users/Shared/dotfiles/config
```

### Second (and any additional) account

The `com.dotfiles.bootstrap` LaunchAgent auto-runs bootstrap at each login,
so **no manual step is required for most accounts.** The agent:

1. Runs on first login (before opening any GUI/CLI tools).
2. Creates per-user skeleton dirs and writes `$HOME/.zshenv → shared .zshenv`.
3. Is idempotent — subsequent logins are no-ops.

For the very first login (before the LaunchAgent has run once), do:

```sh
zsh /Users/Shared/dotfiles/bootstrap.zsh
exec zsh
```

After that, the agent handles re-runs automatically.

### Manual LaunchAgent management

```sh
# Load (start)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dotfiles.bootstrap.plist

# Unload (stop)
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dotfiles.bootstrap.plist

# Check status
launchctl list | grep dotfiles

# View bootstrap log
cat ~/.local/state/dotfiles/bootstrap.log
```

## How bootstrap works

1. **Pre-flight.** Verifies `git` is on `PATH` and `/Users/Shared/dotfiles` exists.
2. **Migration check.** If `~/.local` is a symlink (old single-account layout),
   removes it so real per-user dirs can be created below.
3. **Shared skeleton.** `mkdir -p` for shared dirs under `/Users/Shared/dotfiles`
   (idempotent — already exist after first account).
4. **Per-user skeleton.** `mkdir -p` for `~/.local/state/*`, `~/.cache/npm`,
   `~/.config/<tool>`, `~/Library/LaunchAgents`, etc.
5. **Git.** Adds `safe.directory` to the shared git config; ensures
   `core.sharedRepository=group`. First account runs `git init`; others skip.
6. **`~/.zshenv`.** Writes canonical env vars to `config/zsh/.zshenv` (tracked in git;
   uses `$HOME` which expands per-account at runtime), then symlinks
   `$HOME/.zshenv → config/zsh/.zshenv`. Both `$HOME/.zshenv` and
   `$ZDOTDIR/.zshenv` resolve to the same file — no separate ZDOTDIR shim needed.
7. **Symlinks.** Walks `HOME_LINKS` + `home_links.conf`; creates `$HOME/<rel> →
   /Users/Shared/dotfiles/<repo-rel>` for tools that hardcode `$HOME` paths.
8. **LaunchAgents.** Installs (copies) `com.dotfiles.bootstrap.plist` and
   `com.dotfiles.guard.plist` to `~/Library/LaunchAgents/` and loads them.

## Permissions model

The shared repo is group-owned by `admin` (both accounts on this Mac are in
`admin`), directories are setgid, and git uses `core.sharedRepository=group`.
This ensures commits from either account preserve group-write permissions.

```sh
sudo chgrp -R admin /Users/Shared/dotfiles
sudo chmod -R g+rwX /Users/Shared/dotfiles
sudo find /Users/Shared/dotfiles -type d -exec chmod g+s {} +
git -C /Users/Shared/dotfiles config core.sharedRepository=group
```

If `admin`-group sharing is too broad, create a dedicated group and change
`core.sharedRepository=group` to use it. The git config key works the same way.

## Verified env vars (2026-06)

| Tool | Env var | Where |
|---|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` | Per-user `$HOME/.config/claude` |
| OpenAI Codex CLI | `CODEX_HOME` | Per-user `$HOME/.config/codex` |
| OpenCode | `OPENCODE_CONFIG_DIR` | Per-user `$HOME/.config/opencode` |
| Hermes | `HERMES_HOME` | Per-user `$HOME/.config/hermes` |
| GnuPG | `GNUPGHOME` | Per-user `$HOME/.config/gnupg` |
| git | `GIT_CONFIG_GLOBAL` | **Shared** `config/git/config` |
| readline | `INPUTRC` | **Shared** `config/readline/inputrc` |
| wget | `WGETRC` | **Shared** `config/wget/wgetrc` |
| Aider — history | `AIDER_CHAT_HISTORY_FILE`, `AIDER_INPUT_HISTORY_FILE` | Per-user state |
| Aider — config file | (none) | Symlink only |
| Gemini CLI | (none — issue #2815 unimplemented) | Symlink only |
| Ollama | (none — hardcodes `$HOME/.ollama`) | Symlink to shared `home/.ollama` |
| less | `LESSHISTFILE` | Per-user state |
| npm | `NPM_CONFIG_CACHE`, `NPM_CONFIG_PREFIX` | Per-user cache + data |
| node | `NODE_REPL_HISTORY` | Per-user state |

**Recheck before each fresh-account setup.** Gemini may add a relocation
env var in a future release; OpenAI may rename `CODEX_HOME`.

## Symlink rule

For each entry in `HOME_LINKS` / `home_links.conf`:

- If `dst` is under `~/.ssh` → refuse, log warning, skip.
- If `src` doesn't exist in the repo → warn, skip (no dead symlinks).
- If `dst` is already a symlink to `src` → log `ok`, skip.
- If `dst` is a symlink pointing elsewhere → `rm` it (cheap to recreate).
- If `dst` is a real file/dir → back up to `<dst>.bak` (or `.bak.<timestamp>`
  if `.bak` is taken), then symlink.

## Adding tools to the symlink map

For tools that don't respect XDG and have no relocation env var:

1. Drop the file or directory into `home/` in this repo.
2. Add an entry to `HOME_LINKS` in `bootstrap.zsh`.
3. Re-run `zsh /Users/Shared/dotfiles/bootstrap.zsh`.

## First-run housekeeping (orphaned configs)

Run bootstrap **before** opening any GUI/CLI tools on the fresh account.
Anything launched first writes to its default location because `$XDG_CONFIG_HOME`
isn't set yet. The LaunchAgent handles this for logins after the first one.

If you got bit anyway:

```sh
# XDG-respecting apps that fell back to default ~/.config:
mv ~/.config/<tool>  /Users/Shared/dotfiles/config/<tool>

# Per-user tool dirs — move then re-run bootstrap:
# (bootstrap creates the right per-user dirs; just make sure they're empty first)

# Clean up empty parent dirs:
rmdir ~/.config ~/.local/state ~/.local 2>/dev/null
```

For `gh` specifically: if `~/.config/gh/hosts.yml` exists *and* you have a
`/Users/Shared/dotfiles/config/gh/hosts.yml`, compare sizes before merging —
the `~/.config/` one is usually the live one (most recent token).

## Caveats

- **Codex `CODEX_HOME`** holds config *and* logs (`$CODEX_HOME/log`). Not strictly
  XDG-pure, but Codex only exposes one variable.
- **Gemini** needs a symlink — changing `$HOME` is not a viable fallback.
- **Aider config file** needs a symlink or an alias:
  ```sh
  alias aider="aider --config $XDG_CONFIG_HOME/aider/config.yml"
  ```
- **Ollama** shares models and config between accounts (both symlink `~/.ollama →
  /Users/Shared/dotfiles/home/.ollama`). Per-user identity (`id_ed25519`) and
  history are machine-level, so sharing is safe.
- **`~/.ssh`** is explicitly off-limits to the script.
- **Shared `ZDOTDIR`** means both accounts run the same `.zshrc`/`.zprofile`.
  Account-specific shell tweaks must use `$HOME`-conditional logic, not edits
  to the shared rc.
- **Homebrew** is not configured by this script. `brew shellenv` belongs in
  `$ZDOTDIR/.zprofile`. Homebrew on this Mac is owned by `mabue`; to run brew
  from another account: `sudo -u mabue -H brew bundle --file=/Users/Shared/dotfiles/Brewfile`.

## dotfiles-guard

A per-user background LaunchAgent that monitors `$HOME` every 30 minutes for
new dotfiles.

| Scenario | Action |
|---|---|
| Unknown dotfile appears | Logs + macOS notification (does **not** auto-move) |
| `.bak` backup file | Quarantined to `~/.local/state/guard/quarantine/` |
| New `~/.config/<tool>` dir | Relocated to `config/<tool>` in shared repo + symlinked back |
| Known tools (`.ollama`, `.config/linearmouse`, etc.) | Allowlisted — silently ignored |

State (logs, quarantine) is per-user at `~/.local/state/guard/`.

### LaunchAgent management

```sh
# Load
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dotfiles.guard.plist

# Unload
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.dotfiles.guard.plist

# Status
launchctl list | grep dotfiles

# Preview (no changes)
/Users/Shared/dotfiles/bin/dotfiles-guard --dry-run

# Logs
cat ~/.local/state/guard/guard.log
```

## macOS packages

```sh
sudo -u mabue -H brew bundle --file=/Users/Shared/dotfiles/Brewfile
```

Or if running as the Homebrew owner (`mabue`):

```sh
brew bundle --file=/Users/Shared/dotfiles/Brewfile
```

## Not in scope

- Installing Homebrew, mise, asdf, or any tool.
- Migrating or reading existing configs out of `$HOME`.
- Configuring MCP servers — each AI agent creates its own settings on first run.
- Touching `~/.ssh`.
- `git push` or setting a remote.

## Future ideas

- Switch to **GNU Stow** or **chezmoi** when `HOME_LINKS` grows past ~20 entries.
- **macOS `defaults`** automation as a third bootstrap phase.
- **Per-machine variants** via a `local.zshenv` (sourced last, gitignored).
