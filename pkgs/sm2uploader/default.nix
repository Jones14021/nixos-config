{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
}:

buildGoModule rec {
  pname = "sm2uploader";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "Jones14021";
    repo = "sm2uploader";
    rev = "v${version}";
    hash = "sha256-VotMaDoYmoklgYKnWE3fF7/FZ0Ysm9dsEL1TxxCxOIs=";
  };

  # Required since the project uses a go.mod file
  vendorHash = "sha256-hmxcQBdTegeMegQRUuPJU1bX4THhVQjCr4nA74QL4CE=";

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram "$out/bin/sm2uploader" \
      --add-flags "--web-interface --host 10.0.2.190"
  '';

  # Replicates the Makefile's build flags
  ldflags = [
    "-s"
    "-w"
    "-X" "main.Version=${version}"
  ];

  meta = with lib; {
    description = "A command-line tool to send gcode files to Snapmaker Printers via WiFi connection";
    homepage = "https://github.com/Jones14021/sm2uploader";
    license = licenses.mit;
    mainProgram = "sm2uploader";
    maintainers = [ ];
  };
}
