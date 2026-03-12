{ lib, stdenv, makeWrapper, python3, iproute2, wireguard-tools, curl, inetutils, tcpdump }:

stdenv.mkDerivation {
  pname = "dns-leak-test";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [ python3 ];

  installPhase = ''
    mkdir -p $out/bin
    
    cp dns-leak-test.py $out/bin/dns-leak-test
    chmod +x $out/bin/dns-leak-test
    
    # Wrap the python script with the required system binaries
    wrapProgram $out/bin/dns-leak-test \
      --prefix PATH : ${lib.makeBinPath [ iproute2 wireguard-tools curl inetutils tcpdump]}
  '';
}
