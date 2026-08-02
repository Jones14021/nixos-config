{ pkgs, ... }:

let
  freecadVersion = "1.1.3";
  freecadAppImageName = "FreeCAD_${freecadVersion}-Linux-x86_64-py311.AppImage";
  freecadAppImage = pkgs.fetchurl {
    url = "https://github.com/FreeCAD/FreeCAD/releases/download/${freecadVersion}/${freecadAppImageName}";
    sha256 = "sha256-OoU+tp7llfd58iVdv4CnZZJpgdj/aJA87+5N+wOo9e8=";
  };
  freecadAppDir = pkgs.appimageTools.extractType2 {
    pname = "freecad";
    version = freecadVersion;
    src = freecadAppImage;
  };
  freecadApp = pkgs.appimageTools.wrapType2 {
    pname = "freecad";
    version = freecadVersion;
    src = freecadAppImage;
    extraInstallCommands = ''
      # Reuse upstream desktop metadata so KDE app search/menu work as expected.
      desktopFile="$(find ${freecadAppDir} -type f -path '*/share/applications/*.desktop' | head -n1)"
      if [ -z "$desktopFile" ]; then
        desktopFile="$(find ${freecadAppDir} -maxdepth 2 -type f -name '*.desktop' | head -n1)"
      fi
      install -Dm444 "$desktopFile" $out/share/applications/freecad.desktop
      sed -i 's|^Exec=.*|Exec=freecad %F|' $out/share/applications/freecad.desktop

      if [ -d ${freecadAppDir}/usr/share/icons ]; then
        mkdir -p $out/share
        cp -r ${freecadAppDir}/usr/share/icons $out/share/
      fi

      if [ -f ${freecadAppDir}/freecad.svg ]; then
        install -Dm444 ${freecadAppDir}/freecad.svg $out/share/icons/hicolor/scalable/apps/freecad.svg
      fi
    '';
  };
in
{
  environment.systemPackages = [
    freecadApp
  ];
}