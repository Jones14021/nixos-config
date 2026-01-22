{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation {
  pname = "textconnect";
  version = "1.0.0";

  src = ./.;

  buildInputs = [
    pkgs.inkscape
    pkgs.bash
  ];

  installPhase = ''
    mkdir -p $out/bin
    install -m755 textconnect.sh $out/bin/textconnect
  '';

  meta = with pkgs.lib; {
    description = "Prepare SVG text for laser cutting (text to path, union, offset)";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
