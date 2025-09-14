## good to knows:
#
# * If Calibre shows KFX-ZIP imports, it typically means KFX Input ran but DRM removal didn’t,
#   so ensure DeDRM is present and functioning along with KFX Input.
#
# * After the ZIP is present, Calibre still needs an initial, manual “Load plugin from file”
#   which is typically required due to Calibre’s trust prompt model
#
# * how to use with Kindle-on-Android:
#   https://www.reddit.com/r/Calibre/comments/1is090x/feb_2025_macfriendly_android_emulator_guide_for/?tl=de
#
#    1. adb backup com.amazon.kindle (results in *.ab file)
#    2. adb pull /sdcard/Android/data/com.amazon.kindle/files /tmp/android-kindle-files
#    3. Calibre --> Settings --> Plugins --> DeDRM --> Edit Plugin --> (+) Kindle for Android --> select .ab file
#    4. open /tmp/android-kindle-files in Calibre (open directory with subdirectories)

{ config, pkgs, lib, ... }:

let
  dedrmZip = pkgs.fetchFromGitHub {
    owner = "noDRM";
    repo = "DeDRM_tools";
    rev = "v10.0.3";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-BqRcN7ItZdB4d1MOLzsDXCruViyTOt395x/kJLHxOIs=";
  };

  kfxInput = pkgs.fetchFromGitHub {    
    owner = "kluyg";
    repo = "calibre-kfx-input";
    rev = "main";
    # To discover the correct sha256, temporarily set sha256 = lib.fakeSha256;
    sha256 = "sha256-wO+dsF23c6p8jPpHKWHrSnFNpo92lHxLGNX+NYYZnHE="; # Git SHA-1: 44db6b6ee8c0094a98c33770575a9070ddb90fda, version 2.25.0
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
