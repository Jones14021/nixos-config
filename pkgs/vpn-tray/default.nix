{ lib, stdenv, wrapQtAppsHook, qtbase, qtwayland, python3, systemd }:

stdenv.mkDerivation {
  pname = "vpn-tray";
  version = "1.0.0";
  
  src = ./.;

  # Inject the Qt6 Wayland/X11 wrappers
  nativeBuildInputs = [ wrapQtAppsHook ];
  
  # Prevent the hook from trying to auto-wrap things, we will do it manually
  dontWrapQtApps = true;
  
  # Explicitly include qtbase and qtwayland so wrapQtAppsHook can find the Wayland/X11 plugins
  buildInputs = [
    qtbase
    qtwayland
    (python3.withPackages (ps: with ps; [ pyqt6 ]))
  ];

  installPhase = ''
    mkdir -p $out/bin $out/share/applications $out/etc/xdg/autostart
    
    # Copy the script
    cp vpn-tray.py $out/bin/vpn-tray
    chmod +x $out/bin/vpn-tray

    # Generate the KDE Desktop Entry
    cat > $out/share/applications/vpn-tray.desktop <<EOF
[Desktop Entry]
Name=WireGuard Tray Manager
Exec=$out/bin/vpn-tray
Icon=network-vpn
Type=Application
Categories=Network;
Terminal=false
X-KDE-autostart-after=panel
EOF

    # Autostart with Plasma
    ln -s $out/share/applications/vpn-tray.desktop $out/etc/xdg/autostart/vpn-tray.desktop
  '';

  # Manually wrap the python script to include the systemd PATH and the Qt environment
  postFixup = ''
    wrapQtApp $out/bin/vpn-tray \
      --prefix PATH : ${lib.makeBinPath [ systemd ]}
  '';
}
