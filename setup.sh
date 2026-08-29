#!/usr/bin/env bash
#
# setup.sh - Install common utilities on a fresh GCP Ubuntu box.
#
# Reconstructed from shell history. Installs, in order:
#   - base apt packages (git, htop, tmux, ca-certificates, curl)
#   - uv (Astral) + Python 3.12
#   - Docker CE (official repo) + rootless-for-user group config
#   - an ed25519 SSH key (if none exists)
#
# Safe to re-run: every step checks for existing state before acting.
#
# Usage:
#   ./setup.sh                 # run everything
#   ./setup.sh docker uv       # run only the named steps
#
# Steps: apt  uv  python  docker  sshkey

set -euo pipefail

APT_PACKAGES=(git htop tmux ca-certificates curl)
PYTHON_VERSION="3.12"
SSH_KEY="${HOME}/.ssh/id_ed25519"
SSH_KEY_COMMENT="${USER}@$(hostname)"

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
skip() { printf '    \033[1;33m(skip)\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

require_not_root() {
  if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your normal user (it will call sudo when needed), not as root." >&2
    exit 1
  fi
}

apt_installed() { dpkg -s "$1" >/dev/null 2>&1; }

step_apt() {
  local missing=()
  for pkg in "${APT_PACKAGES[@]}"; do
    if apt_installed "${pkg}"; then
      skip "${pkg} already installed"
    else
      missing+=("${pkg}")
    fi
  done

  if [ ${#missing[@]} -eq 0 ]; then
    skip "all base packages already installed"
    return
  fi

  log "Installing base packages: ${missing[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${missing[@]}"
}

step_uv() {
  if have uv; then
    skip "uv already installed ($(uv --version))"
  else
    log "Installing uv (Astral)"
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi
  # uv installs to ~/.local/bin; make it usable for the rest of this script.
  export PATH="${HOME}/.local/bin:${PATH}"
}

step_python() {
  if ! have uv; then
    export PATH="${HOME}/.local/bin:${PATH}"
  fi
  if ! have uv; then
    echo "uv is required for the python step; run the 'uv' step first." >&2
    exit 1
  fi
  if uv python list --only-installed 2>/dev/null | grep -q "cpython-${PYTHON_VERSION}\."; then
    skip "Python ${PYTHON_VERSION} already installed via uv"
  else
    log "Installing Python ${PYTHON_VERSION} via uv"
    uv python install "${PYTHON_VERSION}"
  fi
}

step_docker() {
  if have docker && dpkg -s docker-ce >/dev/null 2>&1; then
    skip "Docker CE already installed ($(docker --version))"
  else
    log "Installing Docker CE from the official repository"
    for pkg in ca-certificates curl; do
      apt_installed "${pkg}" || sudo apt-get install -y "${pkg}"
    done
    sudo install -m 0755 -d /etc/apt/keyrings

    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
      sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
      sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt-get update -y
    sudo apt-get install -y \
      docker-ce \
      docker-ce-cli \
      containerd.io \
      docker-buildx-plugin \
      docker-compose-plugin
  fi

  sudo systemctl enable --now docker

  # Let the current user run docker without sudo.
  if getent group docker >/dev/null 2>&1; then
    skip "docker group already exists"
  else
    sudo groupadd docker
  fi
  if id -nG "${USER}" | tr ' ' '\n' | grep -qx docker; then
    skip "${USER} already in docker group"
  else
    log "Adding ${USER} to the docker group"
    sudo usermod -aG docker "${USER}"
    echo "    Log out and back in (or run 'newgrp docker') for this to take effect."
  fi
}

step_sshkey() {
  if [ -f "${SSH_KEY}" ]; then
    skip "SSH key already exists at ${SSH_KEY}"
  else
    log "Generating an ed25519 SSH key at ${SSH_KEY}"
    ssh-keygen -t ed25519 -C "${SSH_KEY_COMMENT}" -f "${SSH_KEY}" -N ""
  fi
  echo
  echo "Public key (add to GitHub / GCP as needed):"
  cat "${SSH_KEY}.pub"
}

main() {
  require_not_root

  local steps=("$@")
  if [ ${#steps[@]} -eq 0 ]; then
    steps=(apt uv python docker sshkey)
  fi

  for step in "${steps[@]}"; do
    case "${step}" in
      apt)    step_apt ;;
      uv)     step_uv ;;
      python) step_python ;;
      docker) step_docker ;;
      sshkey) step_sshkey ;;
      *) echo "Unknown step: ${step}" >&2; exit 1 ;;
    esac
  done

  log "Done."
}

main "$@"
