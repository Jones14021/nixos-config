{ lib
, buildGoModule
, fetchFromGitHub
, go
, pkg-config
, wrapGAppsHook
, gtk3
, libayatana-appindicator
, wireguard-tools
, openresolv
}:

buildGoModule rec {
  pname = "wireguird";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "UnnoTed";
    repo  = "wireguird";
    rev   = "v${version}";
    sha256 = "sha256-iv0/HSu/6IOVmRZcyCazLdJyyBsu5PyTajLubk0speI=";
  };

  vendorHash = "sha256-/MeaomhmQL3YNrR4a0ihGwZAo5Zk8snpJvCSXY93aM8=";

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook
  ];

  buildInputs = [
    gtk3
    libayatana-appindicator
    wireguard-tools
    openresolv
  ];

  ldflags = [ "-s" "-w" ];

  postPatch = ''
    # Raise the language version used for compilation
    sed -i 's/^go 1\.16$/go 1.19/' go.mod
  '';

  postInstall = ''
    # desktop entry
    install -Dm0644 assets/wireguird.desktop $out/share/applications/wireguird.desktop

    # ensure it's searchable in KDE/Plasma
    if ! grep -q '^Keywords=' $out/share/applications/wireguird.desktop; then
        echo 'Keywords=wireguard;vpn;wg;network;tunnel;' >> $out/share/applications/wireguird.desktop
    fi

    # install 128x128 icon and reference by theme name "wireguird"
    if [ -f assets/icons/128.png ]; then
        install -Dm0644 assets/icons/128.png \
        $out/share/icons/hicolor/128x128/apps/wireguird.png
        # normalize Icon field if original desktop file used an absolute path
        sed -i 's|^Icon=.*|Icon=wireguird|' $out/share/applications/wireguird.desktop
    fi
  '';


  meta = with lib; {
    description = "GTK GUI for managing WireGuard tunnels";
    homepage = "https://github.com/UnnoTed/wireguird";
    license = licenses.mit;
    platforms = platforms.linux;
    mainProgram = "wireguird";
  };
}
