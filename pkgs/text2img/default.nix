{ lib, stdenv, makeWrapper, imagemagick }:

stdenv.mkDerivation {
  pname = "text2img";
  version = "1.0.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ imagemagick ];

  installPhase = ''
    mkdir -p $out/bin
    install -m755 text2img.sh $out/bin/text2img
    wrapProgram $out/bin/text2img --prefix PATH : ${lib.makeBinPath [ imagemagick ]}
  '';

  meta = with lib; {
    description = "Render text to images for laser cutting";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
