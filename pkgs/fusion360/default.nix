# reference for mkWindowsApp syntax can be found here:
# https://github.com/emmanuelrosa/sumatrapdf-nix/blob/master/sumatrapdf.nix

# from https://github.com/emmanuelrosa/erosanix/blob/master/pkgs/mkwindowsapp/README.md :

## How can I access Wine tools such as winecfg?

# NOTICE: By default, the Wine registry is not persisted, so if you want to use winecfg to tweak
# things you need to enable registry persistence. See the section *How to persist settings*.
# There's now an environment variable which can be used to get dropped into a shell after setting up the WINEPREFIX.
# Simply set the environment variable `WA_RUN_APP=0` before running the app (launcher).
# When `WA_RUN_APP` is not set to `1`, the WINEPREFIX is set up, but the app is not executed.
# Once in the shell, you can run Wine tools; The WINEPREFIX will already be set.

## If my build fails during the winAppInstall phase, how can I clean things up?

# There's now an environment variable you can set to cause the launcher script to delete the app layer.
# Simply set the `WA_CLEAN_APP` environment variable to `1`. 
# Note that the Windows layer will not be deleted.

{ lib
, mkWindowsApp
, makeDesktopItem
, makeDesktopIcon
, copyDesktopItems
, copyDesktopIcons
, fetchFromGitHub
, fetchurl
, wine
, winetricks
, cabextract
, p7zip
, unzip
, curl
, wget
, samba
, fontconfig
, freetype
, openssl
, alsa-lib
, libpulseaudio
, libGL
, vulkan-loader
, xorg
}:

let
  src = fetchFromGitHub {
    owner = "cryinkfly";
    repo  = "Autodesk-Fusion-360-for-Linux";
    rev   = "v7.7.1";
    sha256 = "sha256-f6uypZGpzP1J2qM1L1VJomvO0tQOR2E/lsmDvDIccSg=";
  };

  runtimeDeps = [
    wine winetricks cabextract p7zip unzip curl wget samba
    fontconfig freetype openssl alsa-lib libpulseaudio libGL vulkan-loader
    xorg.xrandr
  ];
in
mkWindowsApp rec {
  inherit wine;

  pname = "fusion360";
  version = "unstable-mkwindowsapp";

  # Core mkWindowsApp options
  enableMonoBootPrompt = false;
  dontUnpack = true;
  wineArch = "win64";
  enableInstallNotification = true;
  persistRuntimeLayer = false;
  inputHashMethod = "store-path";
  enableVulkan = false; # When enabled, the Direct3D backend is changed from OpenGL to vulkan.
  # Can be used to precisely select the Direct3D implementation.
  #
  # | enableVulkan | rendererOverride | Direct3D implementation |
  # |--------------|------------------|-------------------------|
  # | false        | null             | OpenGL                  |
  # | true         | null             | Vulkan (DXVK)           |
  # | *            | dxvk-vulkan      | Vulkan (DXVK)           |
  # | *            | wine-opengl      | OpenGL                  |
  # | *            | wine-vulkan      | Vulkan (VKD3D)          |
  rendererOverride = null;
  enableHUD = false;
  enabledWineSymlinks = { };

  # Starting with version 10, Wine uses Wayland if it's available. But, usually Wayland compositors enable xwayland,
  # which causes Wine to default to X11.
  # When `graphicsDriver` is set to "auto", Wine is allowed to determine whether to use Wayland or X11.
  # When set to "wayland", DISPLAY is unset prior to running Wine, causing it to use Wayland.
  # When set to "prefer-wayland", DISPLAY is unset only if WAYLAND_DISPLAY is set, causing Wine to use Wayland only when Wayland is available.
  graphicsDriver = "auto";

  nativeBuildInputs = [ unzip copyDesktopItems copyDesktopIcons ];

  # This code will become part of the launcher script.
  # It will execute if the application needs to be installed,
  # which would happen either if the needed app layer doesn't exist,
  # or for some reason the needed Windows layer is missing, which would
  # invalidate the app layer.
  # WINEPREFIX, WINEARCH, AND WINEDLLOVERRIDES are set
  # and wine, winetricks, and cabextract are in the environment.
  winAppInstall = ''
    set -euo pipefail
    export PATH=${lib.makeBinPath runtimeDeps}:$PATH
    # Initialize Wine once to avoid prompts
    wineboot -u || true
    # Optional: .NET Framework 4.8 to satisfy "4.5 or newer" for crash reporting
    winetricks -q dotnet48 || true
    # Run upstream non-interactive installer
    bash "${src}/files/setup/autodesk_fusion_installer_x86-64.sh" --install --default
  '';

  # This code will become part of the launcher script.
  # It will execute after winAppInstall and winAppPreRun (if needed),
  # to run the application.
  # WINEPREFIX, WINEARCH, AND WINEDLLOVERRIDES are set
  # and wine, winetricks, and cabextract are in the environment.
  # Command line arguments are in $ARGS, not $@
  # DO NOT BLOCK. For example, don't run: wineserver -w
  #
  # Launch Fusion 360 by looking up Fusion360.exe under webdeploy
  winAppRun = ''
    set -euo pipefail
    ROOT="$WINEPREFIX/drive_c/users/$USER/AppData/Local/Autodesk/webdeploy/production"
    if [ -d "$ROOT" ]; then
      CAND=$(find "$ROOT" -maxdepth 3 -type f -name Fusion360.exe | head -n1 || true)
    else
      CAND=""
    fi
    if [ -z "$CAND" ]; then
      echo "Fusion360.exe not found under $ROOT"; exit 2
    fi
    wine "$CAND" $ARGS
  '';

  # This is a normal mkDerivation installPhase, with some caveats.
  # The launcher script will be installed at $out/bin/.launcher
  # DO NOT DELETE OR RENAME the launcher. Instead, link to it as shown.
  installPhase = ''
    runHook preInstall
    ln -s $out/bin/.launcher $out/bin/${pname}
    runHook postInstall
  '';

  # Desktop integration
  desktopItems = [
    (makeDesktopItem {
      name = pname;
      exec = pname;
      icon = pname;
      desktopName = "Autodesk Fusion 360";
      categories = [ "Graphics" "Engineering" "Development" ];
    })
  ];

  # Optional icon; set src to an image if available
#  desktopIcon = makeDesktopIcon {
#    name = "fusion360";
#    src = fetchurl {
#      url = "https://images.seeklogo.com/logo-png/48/2/autodesk-fusion-360-logo-png_seeklogo-482400.png";
#      sha256 = "sha256-csON1it28JE2pDeVK/p+wnLdlgabGOi3S0n6t3UTsgU=";
#    };
#  };

  # Optional runtime env
  env = {
    DXVK_STATE_CACHE = "1";
    DXVK_LOG_LEVEL = "error";
  };

  meta = with lib; {
    description = "Autodesk Fusion 360 via Wine using mkWindowsApp (writable runtime layer).";
    homepage = "https://github.com/cryinkfly/Autodesk-Fusion-360-for-Linux";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
