## good to knows:
#
# * If Calibre shows KFX-ZIP imports, it typically means KFX Input ran but DRM removal didn’t,
#   so ensure DeDRM is present and functioning along with KFX Input.
#
# * After the ZIP is present, Calibre still needs an initial, manual “Load plugin from file”
#   which is typically required due to Calibre’s trust prompt model

{ config, pkgs, lib, ... }:

let
  dedrmZip = pkgs.fetchFromGitHub {
    owner = "noDRM";
    repo = "DeDRM_tools";
    rev = "v10.0.3";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-BqRcN7ItZdB4d1MOLzsDXCruViyTOt395x/kJLHxOIs="; # Git SHA-1: 44db6b6ee8c0094a98c33770575a9070ddb90fda
  };

  kfxInput = pkgs.fetchFromGitHub {    
    owner = "kluyg";
    repo = "calibre-kfx-input";
    rev = "main";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-wO+dsF23c6p8jPpHKWHrSnFNpo92lHxLGNX+NYYZnHE=";
  };

  # KFX Input plugin (from Calibre plugin index)
  #kfxInput = pkgs.fetchurl {
  #  # Check the plugin index for the latest versioned URL
  #  # https://plugins.calibre-ebook.com/17457/plugins
  #  url = "https://plugins.calibre-ebook.com/17457/291290.zip"; # 2.26.2
  #  # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
  #  sha256 = lib.fakeSha256;
  #};

in {

  # DeDRM plugin
  home.file.".config/calibre/plugins/DeDRM_plugin.zip".source =
    "${dedrmZip}/DeDRM_plugin.zip";

  # KFX Input plugin
  home.file.".config/calibre/plugins/KFX_Input.zip".source =
    kfxInput;
}
