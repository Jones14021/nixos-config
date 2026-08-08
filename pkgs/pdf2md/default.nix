{ lib, writeShellApplication, uv, coreutils, findutils, stdenv, llamaCpp }:

writeShellApplication {
  name = "pdf2md";
  runtimeInputs = [ uv coreutils findutils llamaCpp ];
  runtimeEnv = {
    LD_LIBRARY_PATH = lib.makeLibraryPath [ stdenv.cc.cc.lib ];
    LLAMA_CPP_BINARY = "${llamaCpp}/bin/llama-server";
  };
  text = builtins.readFile ./pdf2md.sh;

  meta = with lib; {
    description = "Interactive Marker v2.0.0 wrapper to convert files/folders to markdown";
    homepage = "https://github.com/datalab-to/marker/releases/tag/v2.0.0";
    license = licenses.asl20;
    platforms = platforms.linux;
    mainProgram = "pdf2md";
  };
}
