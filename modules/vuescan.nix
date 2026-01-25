# https://github.com/NixOS/nixpkgs/issues/217996

{ stdenv, lib, fetchurl, autoPatchelfHook, gnutar, libgudev, gtk2, glibc, makeDesktopItem
, gtk3, xorg, gdk-pixbuf, pango, cairo, glib, fontconfig, util-linuxMinimal
, systemdMinimal, zlib, gcc, ...
}:
let
  pname = "vuescan";
  version = "9.7";
  desktopItem = makeDesktopItem {
    name = "VueScan";
    desktopName = "VueScan";
    genericName = "Scanning Program";
    comment = "Scanning Program";
    icon = "vuescan";
    terminal = false;
    type = "Application";
    startupNotify = true;
    categories = [ "Graphics" "Utility" ];
    keywords = [ "scan" "scanner" ];

    exec = "vuescan";
  };
in stdenv.mkDerivation rec {
  name = "${pname}-${version}";

   src = fetchurl {
     url = "https://www.hamrick.com/files/vuex6497.tgz";
     hash = "sha256-C9CqWcNwpEseaBbIW7MbB+ErF//1asbRzzboGrWgJzo=";
   };

  # Stripping breaks the program
  dontStrip = true;

  nativeBuildInputs = [ gnutar autoPatchelfHook ];

  buildInputs = [
    gtk3
    gtk2
    xorg.libSM
    libgudev
    glibc
    gdk-pixbuf
    pango
    cairo
    glib
    fontconfig
    xorg.libX11
    util-linuxMinimal
    systemdMinimal
    zlib
    gcc.cc.lib
  ];

  unpackPhase = ''
    tar xfz $src
  '';

  installPhase = ''
    install -m755 -D VueScan/vuescan $out/bin/vuescan

    mkdir -p $out/share/icons/hicolor/scalable/apps/
    cp VueScan/vuescan.svg $out/share/icons/hicolor/scalable/apps/vuescan.svg 

    mkdir -p $out/lib/udev/rules.d/
    cp VueScan/vuescan.rul $out/lib/udev/rules.d/60-vuescan.rules

    mkdir -p $out/share/applications/
    ln -s ${desktopItem}/share/applications/* $out/share/applications
  '';
}
