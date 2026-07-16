#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"
nix shell nixpkgs#python3 nixpkgs#python3Packages.urllib3 -c python3 ./scripts/fetch-profiles.py
nix shell nixpkgs#nixfmt-rfc-style -c nixfmt ./pkgs/versions-new.nix
mv ./pkgs/versions-new.nix ./pkgs/versions.nix
