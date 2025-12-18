{ lib
, stdenv
, makeWrapper
, imagemagick
, potrace
}:

stdenv.mkDerivation {
  pname = "png2svg";
  version = "1.0.0";

  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ imagemagick potrace ];

  installPhase = ''
    mkdir -p $out/bin

    install -m755 png2svg.sh $out/bin/png2svg

    wrapProgram $out/bin/png2svg \
      --prefix PATH : ${lib.makeBinPath [
        imagemagick
        potrace
      ]}
  '';

  meta = with lib; {
    description = "PNG to real SVG vectorization tool using ImageMagick + Potrace";
    license = licenses.mit;
    platforms = platforms.linux;
  };
}
