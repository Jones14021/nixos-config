{ unstablePkgs, ... }:

{
  # Each declarative extension is linked into ~/.vscode/extensions, leaving
  # the same directory available for normal Marketplace installs.
  programs.vscode = {
    enable = true;
    package = unstablePkgs.vscode.override {
      commandLineArgs = "--disable-gpu --disable-gpu-sandbox";
    };
    profiles.default.extensions = with unstablePkgs.vscode-extensions; [
      jnoortheen.nix-ide
      mhutchie.git-graph
      ms-python.python
      ms-python.vscode-pylance
      ms-python.debugpy
      ms-python.vscode-python-envs
      ms-toolsai.jupyter
      ms-python.black-formatter
      ms-python.isort
      ms-python.flake8
      ms-python.mypy-type-checker
      ms-vscode-remote.vscode-remote-extensionpack
      ms-vscode-remote.remote-containers
      ms-azuretools.vscode-docker
      ms-azuretools.vscode-containers
      yzhang.markdown-all-in-one
      davidanson.vscode-markdownlint
      mechatroner.rainbow-csv
      vscjava.vscode-java-pack
    ];
  };
}
