# dotfiles

XDG-organized fresh-account dotfiles. `bootstrap.zsh` sets up a layout
where the only file in `$HOME` is `~/.zshenv`; everything else lives
under `~/dotfiles/`.

## Layout

```
~/dotfiles/
├── README.md
├── bootstrap.zsh            # the bootstrap script
├── .gitignore
├── .git/
├── config/                  # $XDG_CONFIG_HOME
│   ├── zsh/                 # $ZDOTDIR
│   ├── git/
│   ├── gnupg/               # $GNUPGHOME
│   ├── readline/            # holds inputrc
│   ├── wget/                # holds wgetrc
│   ├── claude/              # $CLAUDE_CONFIG_DIR
│   ├── codex/               # $CODEX_HOME
│   ├── gemini/              # symlink target for ~/.gemini
│   ├── opencode/            # $OPENCODE_CONFIG_DIR
│   └── aider/
├── data/                    # $XDG_DATA_HOME
├── state/                   # $XDG_STATE_HOME
│   ├── less/                # less history file
│   └── aider/               # aider chat + input history
├── cache/                   # $XDG_CACHE_HOME
└── home/                    # files that must live in $HOME
```

All `config/<tool>/` and the `home/` mirror start **empty**. They fill
up as you (a) commit configs you want versioned into `home/` and (b)
let tools create their own configs by running them.

## Usage on a fresh account

```sh
git clone https://github.com/<your-fork>/dotfiles ~/dotfiles
zsh ~/dotfiles/bootstrap.zsh
exec zsh                                 # pick up the new env vars
```

Idempotent — run it again any time. Every step prints `ok` / `exists`
/ `(none)` on the second run; zero `.bak` files created.

## How it works

1. **Pre-flight.** Verifies `git` is on `PATH`.
2. **Skeleton dirs.** `mkdir -p` for every entry in `SKELETON` inside
   `bootstrap.zsh`.
3. **`git init`.** Initializes the repo if not already one.
4. **Writes `~/.zshenv`.** The only dotfile in `$HOME`. Sets `XDG_*`
   vars and tool-specific relocation env vars (see table below). If
   an existing `.zshenv` differs from the canonical content, it gets
   backed up to `.zshenv.bak` (or `.bak.<timestamp>` if `.bak` is
   taken) before being overwritten.
4b. **`$ZDOTDIR/.zshenv` shim.** Symlinks `$XDG_CONFIG_HOME/zsh/.zshenv`
   → `~/.zshenv`. zsh's startup rules: when `$ZDOTDIR` is exported in
   the environment, zsh reads `$ZDOTDIR/.zshenv` instead of
   `~/.zshenv`. Without the shim, any `exec zsh` from a shell that
   already has `ZDOTDIR` in env silently skips `~/.zshenv` — new env
   vars don't reach the new shell until logout + login. The shim
   makes both paths resolve to the same file.
5. **Symlink loop.** Walks `HOME_LINKS` and symlinks each
   `$HOME/<file>` to its repo counterpart in `home/`. Empty by default.

### Symlink rule

For each entry in `HOME_LINKS`:

- If `dst` is under `~/.ssh` → refuse, log warning, skip.
- If `src` doesn't exist in the repo → warn, skip (no dead symlinks).
- If `dst` is already a symlink to `src` → log `ok`, skip.
- If `dst` is a symlink pointing elsewhere → `rm` it (cheap to
  recreate).
- If `dst` is a real file/dir → back up to `<dst>.bak` (or
  `.bak.<timestamp>` if `.bak` taken), then symlink.

Backups are never overwritten. Restoring a backup is `mv <path>.bak
<path>`.

## Adding tools to the symlink map

For tools that don't respect XDG and have no relocation env var (e.g.,
Gemini CLI's `~/.gemini` directory, aider's `~/.aider.conf.yml`):

1. Drop the file or directory into `home/` in this repo.
2. Add an entry to `HOME_LINKS` in `bootstrap.zsh`:
   ```zsh
   HOME_LINKS=(
     .gemini           home/.gemini
     .aider.conf.yml   home/.aider.conf.yml
   )
   ```
3. Re-run `zsh ~/dotfiles/bootstrap.zsh`.

## Verified env vars (2026-06)

| Tool | Env var | Status |
|---|---|---|
| Claude Code | `CLAUDE_CONFIG_DIR` | ✓ relocates entire `~/.claude` |
| OpenAI Codex CLI | `CODEX_HOME` | ✓ defaults `~/.codex` |
| OpenCode | `OPENCODE_CONFIG_DIR` | ✓ |
| Aider — history | `AIDER_CHAT_HISTORY_FILE`, `AIDER_INPUT_HISTORY_FILE` | ✓ |
| Aider — config file | (none) | symlink only |
| Gemini CLI | (none — issue #2815 unimplemented) | symlink only |
| Ollama | (none — hardcodes `$HOME/.ollama`) | symlink only (active in `HOME_LINKS`) |
| git | `GIT_CONFIG_GLOBAL` | ✓ writes go to `$XDG_CONFIG_HOME/git/config` |
| GnuPG | `GNUPGHOME` | ✓ |
| less | `LESSHISTFILE` | ✓ |
| readline | `INPUTRC` | ✓ |
| wget | `WGETRC` | ✓ |
| npm | `NPM_CONFIG_CACHE`, `NPM_CONFIG_PREFIX` | ✓ cache + global install root |
| node | `NODE_REPL_HISTORY` | ✓ relocates `~/.node_repl_history` |

**Recheck before each fresh-account setup.** Gemini may add a relocation
env var in a future release; OpenAI may rename `CODEX_HOME`; Anthropic
may expose more `CLAUDE_CODE_*` path vars. Authoritative sources:

- Claude Code: https://code.claude.com/docs/en/claude-directory
- Codex: https://developers.openai.com/codex/config-advanced
- OpenCode: https://opencode.ai/docs/config
- Aider: https://aider.chat/docs/config/options.html
- Gemini issue: https://github.com/google-gemini/gemini-cli/issues/2815

## First-run housekeeping (orphaned configs)

Run bootstrap **before** opening any GUI/CLI tools on the fresh account.
Anything you launch first writes to its default location because
`$XDG_CONFIG_HOME` isn't set yet, and those configs stay there orphaned
after bootstrap runs.

**The trap that bites everyone.** Pasting a multi-line block right after
`zsh ~/dotfiles/bootstrap.zsh && exec zsh` can run commands in the
*pre-exec* shell where the new env vars aren't loaded yet. Always wait
for a fresh prompt after `exec zsh` and verify with
`print $XDG_CONFIG_HOME` before pasting tool commands.

If you got bit anyway, sweep these locations:

```sh
# XDG-respecting apps that fell back to default ~/.config:
mv ~/.config/<tool>   ~/dotfiles/config/<tool>

# State files that fell back to default ~/.local/state:
mv ~/.local/state/<tool>  ~/dotfiles/state/<tool>
mv ~/.local/state/lesshst ~/dotfiles/state/less/history

# Apps that ignore XDG entirely (write to ~/.<tool>):
mv ~/.<tool> ~/dotfiles/home/.<tool>
# Add `.tool  home/.<tool>` to HOME_LINKS in bootstrap.zsh, re-run script.

# Clean up empty parent dirs:
rmdir ~/.config ~/.local/state ~/.local 2>/dev/null
```

For `gh` specifically: if `~/.config/gh/hosts.yml` exists *and* you have
a `~/dotfiles/config/gh/hosts.yml`, the `~/.config/` one is usually the
live one (it has the most recent token). Compare sizes before merging.

## Caveats

- **Codex `CODEX_HOME`** holds config *and* logs (`$CODEX_HOME/log`).
  Not strictly XDG-pure, but Codex only exposes one variable, so we
  live with it.
- **Gemini** needs a symlink — changing `$HOME` is not a viable fallback
  (Gemini's OAuth caches break in unexpected ways).
- **Aider config file** needs a symlink or an alias:
  ```sh
  alias aider="aider --config $XDG_CONFIG_HOME/aider/config.yml"
  ```
- **Ollama** hardcodes `$HOME/.ollama` with no env var. Already in
  `HOME_LINKS`; on first run, `mv ~/.ollama ~/dotfiles/home/.ollama`
  before re-running bootstrap if the tool wrote to `$HOME` first.
- **`~/.ssh`** is explicitly off-limits to the script. Manage SSH config
  separately.
- **Homebrew** is *not* configured by this script. `brew shellenv`
  belongs in `$ZDOTDIR/.zprofile` (login shells), not `~/.zshenv`.
  Install brew with the upstream installer; add a `.zprofile` under
  `config/zsh/` containing:
  ```sh
  eval "$(/opt/homebrew/bin/brew shellenv)"
  ```

## Not in scope

- Installing Homebrew, mise, asdf, or any tool.
- Migrating or reading existing configs out of `$HOME`.
- Configuring MCP servers — each AI agent creates its own settings
  (intentionally empty) on first run inside the new XDG location.
- Touching `~/.ssh`.
- `git push` or setting a remote.

## Future ideas

- Switch to **GNU Stow** or **chezmoi** when `HOME_LINKS` grows past
  ~20 entries.
- **Brewfile + `brew bundle`** as a sibling bootstrap script.
- **macOS `defaults`** and `~/Library/LaunchAgents` automation as a
  third bootstrap.
- **Per-machine variants** via a `local.zshenv` (sourced last,
  gitignored).
