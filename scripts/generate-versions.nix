pkgs:
pkgs.writeShellApplication {
  name = "generate-versions";

  runtimeInputs = [
    pkgs.python3
    pkgs.alejandra
    pkgs.uutils-coreutils
  ];

  text = ''
    if ${pkgs.git}/bin/git rev-parse --show-toplevel >/dev/null 2>&1; then
      cd "$(${pkgs.git}/bin/git rev-parse --show-toplevel)"
    fi

    python3 ./scripts/fetch_profiles.py

    echo "INFO: Formatting Minecraft versions"
    alejandra --quiet ./pkgs/versions-new.nix

    echo "INFO: Moving file"
    uutils-mv ./pkgs/versions-new.nix ./pkgs/versions.nix
  '';
}
