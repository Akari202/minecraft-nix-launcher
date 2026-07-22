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
    echo "INFO: Formatting Fabric versions"
    alejandra --quiet ./pkgs/fabric-versions-new.nix
    echo "INFO: Formatting Modrinth versions"
    alejandra --quiet ./pkgs/modrinth-versions-new.nix

    echo "INFO: Moving files"
    uutils-mv ./pkgs/versions-new.nix ./pkgs/versions.nix
    uutils-mv ./pkgs/fabric-versions-new.nix ./pkgs/fabric-versions.nix
    uutils-mv ./pkgs/modrinth-versions-new.nix ./pkgs/modrinth-versions.nix
  '';
}
