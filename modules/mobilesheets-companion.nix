# see documentation for declarative-flatpak https://github.com/in-a-dil-emma/declarative-flatpak
{ config, lib, pkgs, ... }:
let
  downloadDir = "/tmp/declarative-flatpak";
  downloadPath = "${downloadDir}/mobilesheets-companion.flatpak";
in
{
  services.flatpak.enable = true;

  # preInit runs before managing remotes/apps; fetch the out-of-tree flatpakref
  services.flatpak.preInstallCommand = ''
    set -eu
    install -m 0755 -d ${downloadDir}
    curl --fail --location \
      --output ${downloadPath} \
      "https://www.zubersoft.download/mobilesheets.flatpak"
    chmod 0644 ${downloadPath}
  '';

  # required so that the runtime dependency can be installed
  services.flatpak.remotes = {
    "flathub" = "https://dl.flathub.org/repo/flathub.flatpakrepo";      
  };

  # Declare the out-of-tree flatpak via local file; no sha256
  services.flatpak.packages = [
    ":${downloadPath}"
  ];
}
