#!/usr/bin/env bash
set -euo pipefail

# Ensure SHELL is set for downstream installers (e.g., opencode v2) in minimal containers.
export SHELL="${SHELL:-$(command -v bash || echo /bin/sh)}"

mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

log() {
  printf '[devpod-agents] %s\n' "$*"
}

warn() {
  printf '[devpod-agents] WARNING: %s\n' "$*" >&2
}

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    sudo -n "$@"
  else
    return 1
  fi
}

ensure_base_deps() {
  local missing=()
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  command -v tar >/dev/null 2>&1 || missing+=(tar)
  command -v gzip >/dev/null 2>&1 || missing+=(gzip)
  if [ ! -e /etc/ssl/certs/ca-certificates.crt ] && [ ! -d /etc/ssl/certs ]; then
    missing+=(ca-certificates)
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  log "Installing missing base dependencies: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
      run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" || true
  elif command -v apk >/dev/null 2>&1; then
    run_as_root apk add --no-cache "${missing[@]}" || true
  elif command -v dnf >/dev/null 2>&1; then
    run_as_root dnf install -y -q "${missing[@]}" || true
  elif command -v yum >/dev/null 2>&1; then
    run_as_root yum install -y -q "${missing[@]}" || true
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --noconfirm "${missing[@]}" || true
  fi
}

install_ripgrep() {
  if command -v rg >/dev/null 2>&1 && [ "${DEVPOD_AGENTS_UPDATE:-0}" != "1" ]; then
    log "rg already installed ($(command -v rg)); skipping."
    return 0
  fi

  log "Installing ripgrep (rg)..."
  local pkg_ok=0
  if command -v apt-get >/dev/null 2>&1; then
    if run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update -qq &&
       run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ripgrep; then
      pkg_ok=1
    fi
  elif command -v apk >/dev/null 2>&1; then
    if run_as_root apk add --no-cache ripgrep; then
      pkg_ok=1
    fi
  elif command -v dnf >/dev/null 2>&1; then
    if run_as_root dnf install -y -q ripgrep; then
      pkg_ok=1
    fi
  elif command -v yum >/dev/null 2>&1; then
    if run_as_root yum install -y -q ripgrep; then
      pkg_ok=1
    fi
  elif command -v pacman >/dev/null 2>&1; then
    if run_as_root pacman -Sy --noconfirm ripgrep; then
      pkg_ok=1
    fi
  fi

  if [ "$pkg_ok" -eq 1 ] && command -v rg >/dev/null 2>&1; then
    return 0
  fi

  # Fallback: install official BurntSushi/ripgrep static/release binary into ~/.local/bin/rg
  local arch target tag url tmp_dir
  arch="$(uname -m)"
  case "$arch" in
    aarch64|arm64)
      if [ -f /lib/libc.musl-aarch64.so.1 ] || (ldd /bin/ls 2>&1 | grep -q musl); then
        target="aarch64-unknown-linux-musl"
      else
        target="aarch64-unknown-linux-gnu"
      fi
      ;;
    x86_64|amd64)
      target="x86_64-unknown-linux-musl"
      ;;
    *)
      warn "Unsupported architecture for ripgrep fallback: $arch"
      return 1
      ;;
  esac

  tag="$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1 || true)"
  if [ -z "$tag" ]; then
    tag="15.2.0"
  fi
  url="https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${tag}-${target}.tar.gz"
  tmp_dir="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp_dir/rg.tar.gz" &&
     tar -xzf "$tmp_dir/rg.tar.gz" -C "$tmp_dir" &&
     install -m 0755 "$tmp_dir/ripgrep-${tag}-${target}/rg" "$HOME/.local/bin/rg"; then
    rm -rf "$tmp_dir"
    log "Installed rg ${tag} to $HOME/.local/bin/rg"
  else
    rm -rf "$tmp_dir"
    warn "Failed to install ripgrep from $url"
    return 1
  fi
}

install_codex() {
  if [ -x "$HOME/.local/bin/codex" ] && [ "${DEVPOD_AGENTS_UPDATE:-0}" != "1" ]; then
    log "codex already installed ($HOME/.local/bin/codex); skipping."
    return 0
  fi

  log "Installing Codex CLI..."
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
}

install_agy() {
  if [ -x "$HOME/.local/bin/agy" ] && [ "${DEVPOD_AGENTS_UPDATE:-0}" != "1" ]; then
    log "agy already installed ($HOME/.local/bin/agy); skipping."
    return 0
  fi

  if [ "${DEVPOD_AGENTS_UPDATE:-0}" = "1" ] && [ -f "$HOME/.local/bin/agy" ]; then
    rm -f "$HOME/.local/bin/agy"
  fi

  log "Installing Antigravity CLI (agy)..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
}

install_opencode() {
  if [ -x "$HOME/.opencode/bin/opencode" ] && [ "${DEVPOD_AGENTS_UPDATE:-0}" != "1" ]; then
    log "opencode already installed ($HOME/.opencode/bin/opencode); skipping."
    return 0
  fi

  log "Installing OpenCode v2 CLI..."
  curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path
}

link_global_bin() {
  local src="$1"
  local name="$2"
  local dst="/usr/local/bin/$name"

  if [ ! -x "$src" ]; then
    return 0
  fi

  if [ -w "/usr/local/bin" ]; then
    ln -sf "$src" "$dst"
  elif run_as_root ln -sf "$src" "$dst" 2>/dev/null; then
    :
  else
    warn "Could not symlink $dst (no write permission or passwordless sudo)"
  fi
}

ensure_path_block() {
  local rc_file="$1"
  local marker="# >>> devpod-agents PATH >>>"

  if [ ! -f "$rc_file" ]; then
    return 0
  fi

  if grep -Fq "$marker" "$rc_file" 2>/dev/null; then
    return 0
  fi

  cat >> "$rc_file" <<'EOF'

# >>> devpod-agents PATH >>>
export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
# <<< devpod-agents PATH <<<
EOF
}

expose_paths() {
  link_global_bin "$HOME/.local/bin/codex" "codex"
  if [ -x "$HOME/.local/bin/codex-code-mode-host" ]; then
    link_global_bin "$HOME/.local/bin/codex-code-mode-host" "codex-code-mode-host"
  fi
  link_global_bin "$HOME/.local/bin/agy" "agy"
  link_global_bin "$HOME/.opencode/bin/opencode" "opencode"

  if [ -x "$HOME/.local/bin/opencode" ] || [ ! -e "$HOME/.local/bin/opencode" ]; then
    if [ -x "$HOME/.opencode/bin/opencode" ]; then
      ln -sf "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
    fi
  fi

  if [ ! -x /usr/bin/rg ] && [ ! -x /usr/local/bin/rg ] && [ -x "$HOME/.local/bin/rg" ]; then
    link_global_bin "$HOME/.local/bin/rg" "rg"
  fi

  touch "$HOME/.profile" 2>/dev/null || true
  ensure_path_block "$HOME/.profile"
  ensure_path_block "$HOME/.bashrc"
  ensure_path_block "$HOME/.zshrc"
}

write_b64_file() {
  local var_name="$1"
  local dest_path="$2"
  local mode="$3"
  local val="${!var_name:-}"

  if [ -z "$val" ]; then
    return 0
  fi

  if [ -f "$dest_path" ] && [ "${DEVPOD_AGENTS_FORCE_AUTH:-0}" != "1" ]; then
    log "$dest_path already exists; preserving existing file (set DEVPOD_AGENTS_FORCE_AUTH=1 to overwrite)."
    return 0
  fi

  local parent tmp_file
  parent="$(dirname "$dest_path")"
  mkdir -p "$parent"
  tmp_file="$(mktemp "${parent}/.tmp.XXXXXX")"

  if printf '%s' "$val" | base64 -d > "$tmp_file" 2>/dev/null; then
    chmod "$mode" "$tmp_file"
    mv -f "$tmp_file" "$dest_path"
    log "Wrote $dest_path (mode $mode)"
  else
    rm -f "$tmp_file"
    warn "Failed to decode $var_name into $dest_path"
    return 1
  fi
}

import_auth_and_settings() {
  # Codex
  mkdir -p "$HOME/.codex"
  chmod 700 "$HOME/.codex"
  write_b64_file "CODEX_AUTH_B64" "$HOME/.codex/auth.json" 600

  # Antigravity (agy CLI + remote hub)
  mkdir -p "$HOME/.gemini" "$HOME/.gemini/antigravity-cli"
  chmod 700 "$HOME/.gemini"
  write_b64_file "AGY_OAUTH_B64" "$HOME/.gemini/jetski-standalone-oauth-token" 600
  write_b64_file "AGY_OAUTH_B64" "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" 600
  write_b64_file "AGY_SETTINGS_B64" "$HOME/.gemini/antigravity-cli/settings.json" 600

  # OpenCode v2 config files
  mkdir -p "$HOME/.config/opencode" "$HOME/.local/share/opencode"
  write_b64_file "OPENCODE_JSONC_B64" "$HOME/.config/opencode/opencode.jsonc" 644
  write_b64_file "OPENCODE_CLI_JSON_B64" "$HOME/.config/opencode/cli.json" 600
  write_b64_file "OPENCODE_TUI_JSON_B64" "$HOME/.config/opencode/tui.json" 644

  # OpenCode v2 stored credentials
  local marker="$HOME/.local/share/opencode/.devpod-auth-imported"
  if [ -n "${OPENCODE_AUTH_B64:-}" ]; then
    if [ -f "$marker" ] && [ "${DEVPOD_AGENTS_FORCE_AUTH:-0}" != "1" ]; then
      log "OpenCode auth already imported ($marker); skipping."
    elif command -v opencode >/dev/null 2>&1; then
      local tmp_auth
      tmp_auth="$(mktemp "$HOME/.local/share/opencode/.tmp.auth.XXXXXX.json")"
      chmod 600 "$tmp_auth"
      if printf '%s' "$OPENCODE_AUTH_B64" | base64 -d > "$tmp_auth" 2>/dev/null; then
        if opencode auth import --standalone "$tmp_auth" >/dev/null 2>&1 || opencode auth import "$tmp_auth" >/dev/null 2>&1; then
          touch "$marker"
          chmod 600 "$marker"
          log "Imported OpenCode v2 credentials."
        else
          warn "opencode auth import failed."
        fi
      else
        warn "Failed to decode OPENCODE_AUTH_B64."
      fi
      rm -f "$tmp_auth"
    else
      warn "opencode binary not found; skipping auth import."
    fi
  fi
}

print_summary() {
  log "=== DevPod Coding Agents Summary ==="
  for cmd in rg codex agy opencode; do
    local p ver
    p="$(command -v "$cmd" 2>/dev/null || echo 'missing')"
    if [ "$p" != "missing" ]; then
      ver="$("$cmd" --version 2>/dev/null | head -n 1 || echo 'installed')"
    else
      ver="not found"
    fi
    log "  $cmd: $p ($ver)"
  done
  log "  codex auth:    $( [ -f "$HOME/.codex/auth.json" ] && echo present || echo missing )"
  log "  agy hub oauth: $( [ -f "$HOME/.gemini/jetski-standalone-oauth-token" ] && echo present || echo missing )"
  log "  agy cli oauth: $( [ -f "$HOME/.gemini/antigravity-cli/antigravity-oauth-token" ] && echo present || echo missing )"
  log "  opencode:      $( [ -f "$HOME/.local/share/opencode/.devpod-auth-imported" ] && echo imported || echo not-imported )"
}

main() {
  ensure_base_deps
  install_ripgrep
  install_codex
  install_agy
  install_opencode
  expose_paths
  import_auth_and_settings
  print_summary
}

main "$@"
