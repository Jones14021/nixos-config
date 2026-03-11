{ lib, stdenv, makeWrapper, gnugrep, coreutils }:

stdenv.mkDerivation {
  pname = "wireguard-extract-secrets";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    
    cp wireguard-extract-secrets.sh $out/bin/wireguard-extract-secrets
    
    chmod +x $out/bin/wireguard-extract-secrets
    
    wrapProgram $out/bin/wireguard-extract-secrets \
      --prefix PATH : ${lib.makeBinPath [ gnugrep coreutils ]}
  '';

  meta = with lib; {
    description = "Extracts WireGuard secrets from .conf files for NixOS declarative setup";
    mainProgram = "wireguard-extract-secrets";
    platforms = platforms.all;
  };
}
