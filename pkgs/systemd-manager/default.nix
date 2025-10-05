# https://github.com/GuillaumeGomez/systemd-manager

{ lib
, rustPlatform
, fetchFromGitHub
, pkg-config
, gtk3
, glib
, cairo
, gdk-pixbuf
, pango
, atk
, dbus
, polkit
, wrapGAppsHook
}:

rustPlatform.buildRustPackage rec {
  pname = "systemd-manager";
  version = "2024-11-14"; # repo is effectively archived, mention date

  src = fetchFromGitHub {
    owner = "GuillaumeGomez";
    repo = "systemd-manager";
    rev = "1f120c02556d361914c9954abea920dc6f354216";
    hash = "sha256-95xJZSFVEZXksG6HFLHh/hjfeqz/8AlA1oJ9KUUmz+Q=";
  };

  # repo has no cargo.lock file. so set everything here manually
  #
  # for that, the Cargo.lock file was created manually by checking out the git repo
  # temporarily at the correct version and running 'cargo generate-lockfile' then copying the file here
  cargoLock = {
  lockFile = ./Cargo.lock;
  outputHashes = {
    "atk-0.9.0" = "sha256-ny4pXgY9yciLFI7LCD3a35hCT0tkMHU4GNisP1xbOvo=";
    "atk-sys-0.10.0" = "sha256-HuJ+jWC5fj4x0TKreGxFO4mEzqROgSvc+BeuKFACELc=";
    "cairo-rs-0.9.0" = "sha256-rSHlDXVmZv9Wk2MDq2IZITeYcExh/aaZHPuuPuoXRB0=";
    "gdk-0.13.0" = "sha256-xlyMOAQV9lnMz+ChSLq9hPwKtpn3dgybx2eqvtAm+zA=";
    "gdk-pixbuf-0.9.0" = "sha256-+/lbuJxtvazUQz1uRt6PdSWhFWiWYcCdRifbuMnjfDY=";
    "gio-0.9.0" = "sha256-Ck+FY5qwVAO7Oo0UdLSE9K8z3HU5ofZnkTS7ibXhHPg=";
    "glib-0.10.0" = "sha256-jVZht5gO3ihUG5HHR4zUk68JyS3myuRVwkkX+cFgJjY=";
    "gtk-0.9.0" = "sha256-nhoumfZzGHa2Bd9a0KCrY1Kk9CZIT7B6D7V6HuoZYpk=";
    "pango-0.9.0" = "sha256-7sKznGwUjSwtdln22KIuvTpBgS+nBYhJogOdZrmHd1U=";
    };
  };

  postPatch = ''
    ln -s ${./Cargo.lock} Cargo.lock
  '';

  nativeBuildInputs = [
    pkg-config
    wrapGAppsHook
  ];

  buildInputs = [
    gtk3
    glib
    cairo
    gdk-pixbuf
    pango
    atk
    dbus
    polkit
  ];

  # Install desktop file and polkit action if present in assets
  postInstall = ''
    # Install desktop entry
    if [ -f assets/systemd-manager.desktop ]; then

      # remove any existing Keywords= line within the Desktop Entry section and appends a new one with custom terms
      sed -Ei '/^\[Desktop Entry\]/,/^\[/{/^Keywords=/d}' assets/systemd-manager.desktop && \
      printf '%s\n' 'Keywords=systemd;services;units;journal;logs;boot;analyze;manager;dbus;' >> assets/systemd-manager.desktop

      install -Dm644 assets/systemd-manager.desktop \
        $out/share/applications/systemd-manager.desktop
    fi

    # Install polkit policy
    if [ -f assets/org.freedesktop.policykit.systemd-manager.policy ]; then
      install -Dm644 assets/org.freedesktop.policykit.systemd-manager.policy \
        $out/share/polkit-1/actions/org.freedesktop.policykit.systemd-manager.policy
    fi

    # Install pkexec helper if present
    if [ -f assets/systemd-manager-pkexec ]; then
      install -Dm755 assets/systemd-manager-pkexec \
        $out/bin/systemd-manager-pkexec
    fi
  '';

  # gtk-rs expects GTK 3 + friends at runtime; wrapGAppsHook wires env vars
  # No tests upstream
  doCheck = false;

  meta = with lib; {
    description = "GTK3 GUI to manage systemd units with dbus integration";
    homepage = "https://github.com/GuillaumeGomez/systemd-manager";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "systemd-manager";
  };
}
