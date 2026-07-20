pkgs:
pkgs.writeShellApplication {
  name = "generate-versions";

  runtimeInputs = [
    pkgs.python3
    pkgs.python3Packages.urllib3
    pkgs.alejandra
    pkgs.uutils-coreutils
  ];

  text = ''
    set -euo pipefail

    if ${pkgs.git}/bin/git rev-parse --show-toplevel >/dev/null 2>&1; then
      cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
    fi

    python3 ./scripts/fetch_profiles.py

    echo "INFO: Formatting Minecraft versions"
    alejandra --quiet ./pkgs/versions-new.nix
    echo "INFO: Formatting asset versions"
    alejandra --quiet ./pkgs/asset-versions-new.nix

    echo "INFO: Renaming files"
    uutils-mv ./pkgs/versions-new.nix ./pkgs/versions.nix
    uutils-mv ./pkgs/asset-versions-new.nix ./pkgs/asset-versions.nix
  '';
}
