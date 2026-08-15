{ unstablePkgs, ... }:

let
  vscode = unstablePkgs.vscode.override {
    commandLineArgs = "--disable-gpu --disable-gpu-sandbox";
  };
  vscodeWithExtensions = unstablePkgs.vscode-with-extensions.override {
    inherit vscode;
    vscodeExtensions = with unstablePkgs.vscode-extensions; [
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
      ms-azuretools.vscode-docker
      yzhang.markdown-all-in-one
      davidanson.vscode-markdownlint
      mechatroner.rainbow-csv
      vscjava.vscode-java-pack
    ];
  };
in
{
  environment.systemPackages = [ vscodeWithExtensions ];
}