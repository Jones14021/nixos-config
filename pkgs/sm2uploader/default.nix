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
    hash = "sha256-/yU2NJb8uwUSF9lGtK7bd5z20SWuC1Cv+g7rUq1Nqa0=";
  };

  # Required since the project uses a go.mod file
  vendorHash = "sha256-hmxcQBdTegeMegQRUuPJU1bX4THhVQjCr4nA74QL4CE=";

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
