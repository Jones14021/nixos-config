{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "sm2uploader";
  version = "fork-no-modif-to-gcode-files";

  src = fetchFromGitHub {
    owner = "Jones14021";
    repo = "sm2uploader";
    rev = "67144fee861f2e140dea226941a1f11b9eb0f4ff";
    hash = "sha256-e7AJcbCCc6zPQSNJzLxxyfKAnRMEWS48hjVw0UGwH1w=";
  };

  # Required since the project uses a go.mod file
  vendorHash = "sha256-knWgm7ZgDD1dTFB74zgxHnc1RVCNJfcP9kqnyw8JUyA=";

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
