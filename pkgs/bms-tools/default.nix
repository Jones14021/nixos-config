{ lib
, pkgs
, python3Packages
, pkg-config
, gtk3
, gsettings-desktop-schemas
, wrapGAppsHook3
, makeWrapper
}:

python3Packages.buildPythonApplication {
  pname = "bms-tools";
  version = "1.1.4";

  src = pkgs.fetchFromGitLab {
    owner = "bms-tools";
    repo = "bms-tools";
    rev = "v1.1.4";
    sha256 = "sha256-Vb6yq44hOPfXcLm7Yi87nJGkhZ9IHtAaZ1Mcl/psHUQ=";
  };

  format = "setuptools";

  nativeBuildInputs = [
    # pkg-config: exposes GTK3 .pc files so wxPython's C++ build finds headers/libs
    # in the Nix store instead of looking in nonexistent global paths like /usr/include
    pkg-config

    # wrapGAppsHook3: wraps executables in $out/bin with correct XDG_DATA_DIRS,
    # GSETTINGS_SCHEMA_DIR, and icon/theme paths so GTK and Pango don't crash
    # or emit font/schema warnings at runtime
    wrapGAppsHook3
    # Needed to modify the PATH of the ble bridge bash script
    makeWrapper 
  ];

  buildInputs = [
    # gtk3: the C library wxPython's GTK backend links against
    gtk3

    # gsettings-desktop-schemas: provides the GSettings schemas that GTK/Pango
    # expect at runtime. Without this, wxPython triggers Pango-CRITICAL warnings
    # like "pango_font_description_set_size: assertion 'size >= 0' failed"
    # because font/DPI settings cannot be resolved properly on NixOS
    gsettings-desktop-schemas
  ];

  propagatedBuildInputs = with python3Packages; [
    bleak
    pyserial
    xlsxwriter
    # wxpython is the GUI toolkit used by jbd_gui.py (import wx).
    # Must come from Nixpkgs — never let pip build this from source,
    # as it takes 17+ minutes and breaks on Python 3.13
    wxpython
    ble-serial
  ];

  doCheck = false;

  postInstall = ''
    # CLI tool: console_scripts from setup.py/setup.cfg are installed automatically
    # into $out/bin by buildPythonApplication — nothing extra needed here.

    # Remove the broken upstream entry point binary before wrapGAppsHook3 wraps it
    rm $out/bin/bmstools_jbd_gui

    # GUI tool: jbd_gui.py is not a console_script, it lives in ./gui/ and uses
    # relative paths for assets (img/, plugins/), so copy the whole gui tree.
    mkdir -p $out/share/bms-tools/gui
    cp -r gui/* $out/share/bms-tools/gui/

    # Remove dangling symlink that points into the external bms-firmware-jbd repo,
    # which is not part of this source tree. The fw_debug plugin is optional debug
    # tooling and not needed for normal BMS operation.
    rm $out/share/bms-tools/gui/plugins/fw_debug/debug_struct.py

    # Create a launcher in $out/bin. wrapGAppsHook3 will automatically wrap this
    # executable with the correct GTK/GSettings environment variables.
    cat > $out/bin/bms-tools-gui <<EOF
#!/usr/bin/env python3
import sys
import runpy
import os

gui_dir = "$out/share/bms-tools/gui"
os.chdir(gui_dir)
sys.path.insert(0, gui_dir)
runpy.run_path(os.path.join(gui_dir, "jbd_gui.py"), run_name="__main__")
EOF

    chmod +x $out/bin/bms-tools-gui

    # Install the BLE bridge script
    install -Dm755 ${./bms-tools-ble-bridge.sh} $out/bin/bms-tools-ble-bridge

    # Wrap the bash script to ensure it can find 'ble-scan', 'ble-serial', 
    # and 'bluetoothctl' regardless of the user's current environment PATH.
    # Use python3Packages.ble-serial explicitly here to resolve its bin/ path.
    wrapProgram $out/bin/bms-tools-ble-bridge \
      --prefix PATH : ${lib.makeBinPath [ python3Packages.ble-serial pkgs.bluez ]}
  '';

  meta = with lib; {
    description = "BMS Tools (CLI and GUI) for JBD battery management systems";
    homepage = "https://gitlab.com/bms-tools/bms-tools";
    license = licenses.mit;
    maintainers = [ ];
  };
}
