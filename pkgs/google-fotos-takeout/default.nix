{ lib
, stdenv
, fetchurl
, makeWrapper
, bash
, coreutils
, curl
, findutils
, gawk
, gnused
, gnutar
, gzip
, unzip
, rsync
, util-linux
, xdg-utils
, glib
}:

let
  gpth = stdenv.mkDerivation {
    pname = "gpth";
    version = "3.4.3";
    src = fetchurl {
      url = "https://github.com/TheLastGimbus/GooglePhotosTakeoutHelper/releases/download/v3.4.3/gpth-linux";
      sha256 = "sha256-YF15AYjGdHva8tEMohbcd0Oj602dI1TsRBCkVHjlxzU=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      install -m755 $src $out/bin/gpth
    '';
  };
in
stdenv.mkDerivation {
  pname = "google-fotos-takeout";
  version = "1.0.0";
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Install your main CLI
    install -m755 google-fotos-takeout.sh $out/bin/google-fotos-takeout

    # Ensure your script can find all runtime dependencies
    wrapProgram $out/bin/google-fotos-takeout \
      --prefix PATH : ${lib.makeBinPath [
        bash
        coreutils
        curl
        findutils
        gawk
        gnused
        gnutar
        gzip
        unzip
        rsync
        util-linux
        xdg-utils
        glib
        gpth
      ]}

    runHook postInstall
  '';

  meta = with lib; {
    description = "Interactive walkthrough for Google Photos Takeout";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
