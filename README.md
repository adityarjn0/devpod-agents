# devpod-agents

Native DevPod dotfiles bootstrapper for installing and authenticating **Codex** (`codex`), **Antigravity** (`agy`), **OpenCode v2** (`opencode`), and **ripgrep** (`rg`) inside DevPod workspaces.

> Contains **zero secrets** — credentials and clean settings live locally in `~/.config/devpod/agents.env` (`0600`) and are injected transiently during `install-dotfiles` via DevPod's native `--dotfiles-script-env-file` flag.

## One-Time Host Setup

1. Generate your local env file from your macOS credentials:
   ```bash
   ./export-env.sh
   ```
   This writes `~/.config/devpod/agents.env` (`chmod 600`) with base64-encoded snapshots of:
   - `~/.codex/auth.json`
   - `~/.gemini/jetski-standalone-oauth-token` and sanitized `~/.gemini/antigravity-cli/settings.json`
   - `opencode auth export` credentials and `~/.config/opencode/{opencode.jsonc,cli.json,tui.json}`

2. Configure DevPod context options:
   ```bash
   devpod context set-options \
     -o DOTFILES_URL=https://github.com/adityarjn0/devpod-agents \
     -o DOTFILES_SCRIPT=install.sh
   ```

3. For **DevPod.app**, set **Settings -> Additional CLI Flags** to:
   ```text
   --dotfiles-script-env-file=/Users/spacegrep/.config/devpod/agents.env
   ```

## CLI Usage

```bash
devpod up <repo> --dotfiles-script-env-file=~/.config/devpod/agents.env
```

## Refreshing Tokens or Retrofitting Existing Workspaces

- Refresh local env file after re-authenticating on macOS:
  ```bash
  ./export-env.sh
  ```
- Retrofit an existing workspace (or re-run without recreating):
  ```bash
  devpod up <workspace-name> --open-ide=false --dotfiles-script-env-file=~/.config/devpod/agents.env
  ```

## Optional Container Flags

- `DEVPOD_AGENTS_UPDATE=1`: Force updating already-installed binaries (`rg`, `codex`, `agy`, `opencode`).
- `DEVPOD_AGENTS_FORCE_AUTH=1`: Overwrite existing container auth/config files and re-import OpenCode credentials.
