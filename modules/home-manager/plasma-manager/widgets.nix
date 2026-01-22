# Notes: 
# - The install location for user-installed widgets is ~/.local/share/plasma/plasmoids/
# - Each plasmoid must be in its own subdirectory, named according to the plasmoid's unique identifier.
# - Usually, the repo already contains the final plasmoid layout (a metadata.json or metadata.desktop at the root of the widget directory).
#   If so, simply link/copy it into the correct location under ~/.local/share/plasma/plasmoids/<KPlugin.Id>
# - You can find the unique identifier in the metadata.desktop file inside the plasmoid package.
# - After adding or updating plasmoids, you may need to restart Plasma or log out
# - For plasmoids (and generally KPackage content), use copies into $HOME instead of symlinks into the Nix store
#
# Debug with:
# 
# kpackagetool6 --type plasma/applet --list | grep -E 'commandoutput|stdout|netspeed' -i
# plasmoidviewer -a org.kde.simple.stdout

# once copying is possible via home.file (see https://github.com/nix-community/home-manager/issues/3090)
# we can switch to that instead of using the install scripts potentially
# 
# example:
#
#  home.file = {
#    # https://store.kde.org/p/2136636/
#    # Command Output plasmoid (Plasma 6): repo has "package/" directory
#    ".local/share/plasma/plasmoids/com.github.zren.commandoutput" = {
#      source = "${commandoutputSrc}/package";
#      recursive = true;
#      copy = true; # needed to avoid symlink issues with nix store paths
#    };

{ config, pkgs, lib, ... }:

let
  # may need to consider the actual install scripts here in case of more complex plasmoids
  installPlasmoid = id: src: ''
    dst="$HOME/.local/share/plasma/plasmoids/${id}"
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -a --no-preserve=mode,ownership "${src}/." "$dst/"
  '';

  commandoutputSrc = pkgs.fetchFromGitHub {
    owner = "Zren";
    repo = "plasma-applet-commandoutput";
    rev = "v13";
    sha256 = "sha256-Tjnm26EYKXtBM9JBHKI73AMvOW/rQ3qOw2JDYey7EfQ=";
  };

  simpleStdoutSrc = pkgs.fetchFromGitHub {
    owner = "varlesh";
    repo = "org.kde.simple.stdout";
    rev = "3fd922de7ccfcde0789e84c139103471375d5bb0";
    sha256 = "sha256-hgQGuD9ytlNqxpLzz3CnTundsK9B0/pgHrXezbrYdNQ=";
  };

  netspeedWidgetSrc = pkgs.fetchFromGitHub {
    owner = "dfaust";
    repo = "plasma-applet-netspeed-widget";
    rev = "v3.1";
    sha256 = "sha256-lP2wenbrghMwrRl13trTidZDz+PllyQXQT3n9n3hzrg=";
  };
in
{
  home.activation.installPlasmoids = lib.hm.dag.entryAfter ["writeBoundary"] ''

    # https://store.kde.org/p/2136636/
    # Command Output plasmoid (Plasma 6): repo has "package/" directory
    ${installPlasmoid "com.github.zren.commandoutput" "${commandoutputSrc}/package"}

    # https://store.kde.org/p/2339071
    # Simple STDOUT (Plasma 6)
    ${installPlasmoid "org.kde.simple.stdout" "${simpleStdoutSrc}"}

    # https://store.kde.org/p/2136505
    # NetSpeed Widget (Plasma 6)
    ${installPlasmoid "org.kde.netspeedWidget" "${netspeedWidgetSrc}/package"}
    '';
}
