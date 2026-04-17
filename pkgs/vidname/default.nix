{
  lib,
  python3Packages,
  ffmpeg,
  makeWrapper,
}:

let
  # Bundle the Python script into the store
  pythonEnv = python3Packages.python.withPackages (ps: [
    ps.faster-whisper
  ]);
in
python3Packages.buildPythonApplication {
  pname   = "vidname";
  version = "1.0.0";
  format  = "other";   # no setup.py / pyproject.toml

  # We embed the script directly — point src at the directory containing
  # this default.nix so Nix can find vidname.py next to it.
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];

  # faster-whisper is the only runtime Python dep
  propagatedBuildInputs = with python3Packages; [
    faster-whisper
  ];

  # No build step — just install the script
  buildPhase = "true";

  installPhase = ''
    install -Dm755 $src/vidname.py $out/bin/vidname
    # Wrap so that ffmpeg is always on PATH inside the script
    wrapProgram $out/bin/vidname \
      --prefix PATH : ${lib.makeBinPath [ ffmpeg ]}
  '';

  meta = with lib; {
    description = "Auto-title MP4 files via local Whisper transcription + GitHub Copilot";
    license     = licenses.mit;
    maintainers = [];
    platforms   = platforms.linux;
    mainProgram = "vidname";
  };
}
