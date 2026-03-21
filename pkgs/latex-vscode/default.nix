{ pkgs }:

let
  # 1. Define the isolated VS Code environment with the LaTeX Workshop extension.
  vscodeWithLatex = pkgs.vscode-with-extensions.override {
    vscodeExtensions = with pkgs.vscode-extensions; [
      james-yu.latex-workshop
      mhutchie.git-graph
      gruntfuggly.todo-tree
      github.copilot-chat
    ];
  };

  # 2. Define the runtime dependencies
  runtimeDeps = with pkgs; [
    tectonic                # The core LaTeX engine
    biber                   # Required if you use biblatex for bibliography management
    fontconfig              # Required for discovering system fonts (essential for XeTeX/LuaTeX backends)
    coreutils               # Standard utilities often expected by build scripts
    tex-fmt                 # super fast LaTeX formatter written in Rust
    sqlite                  # Used to check the Zotero database for correctness
    # Extract utilities from TeX Live (as used by LaTeX Workshop)
    (texlive.combine {
      inherit (texlive) 
        scheme-minimal      # Basic TeX Live installation with just the essential binaries
        texcount            # For counting words in LaTeX documents, used by some VS Code extensions for word count features
        checkcites;         # For checking bibliography entries, used by some VS Code extensions to validate citations
    })
    ghostscript   # for .eps to .pdf conversion, if needed
    poppler-utils # for pdftotext, which can be used by some VS Code extensions for PDF previewing and searching
  ];

  # 3. Declaratively define the VS Code settings
  settingsJson = builtins.toJSON {
    # --- UI & THEME SETTINGS ---
    "workbench.colorTheme" = "Default Light Modern";
    
    # --- TECTONIC BUILD SETTINGS ---
    "latex-workshop.latex.tools" = [
      {
        name = "tectonic";
        command = "tectonic";
        # IMPORTANT: Use %DOC_EXT% and maintain the order of the flags
        args = [
          "--synctex"
          "--keep-logs"
          "--keep-intermediates"
          "%DOC_EXT%"
        ];
        env = {};
      }
    ];
    "latex-workshop.latex.recipes" = [
      {
        name = "tectonic";
        tools = [ "tectonic" ];
      }
    ];
    
    # Optimize SyncTeX and build behavior
    "latex-workshop.latex.autoBuild.run" = "onFileChange";
    "latex-workshop.view.pdf.viewer" = "tab";

    # Ensures that the viewer jumps to the correct position after compilation
    "latex-workshop.synctex.afterBuild.enabled" = true;
    
    # Ensures that the internal, Nix-independent JavaScript SyncTeX parser is used
    "latex-workshop.synctex.synctexjs.enabled" = true;

    # --- FORMATTING ---
    "[latex]" = {
      "editor.wordWrap" = "wordWrapColumn"; # soft wrap for best practice with versioning tex files
      "editor.wordWrapColumn" = 100;
      "editor.defaultFormatter" = "James-Yu.latex-workshop";
      "editor.formatOnSave" = true;
    };

    "latex-workshop.formatting.latex" = "tex-fmt";

    # --- OTHER SETTINGS ---
    "telemetry.telemetryLevel" = "off";
    "update.mode" = "none";
  };

  # 4. Create the wrapper script.
  # This creates an isolated user data directory and injects the settings.
  wrapperBin = pkgs.writeShellScriptBin "latex-vscode" ''
    # Define an isolated directory for this specific VS Code instance
    VSCODE_DATA_DIR="$HOME/.config/latex-vscode"
    USER_SETTINGS_DIR="$VSCODE_DATA_DIR/User"
    EXTENSIONS_DIR="$VSCODE_DATA_DIR/extensions"
    
    # Ensure the directories exist
    mkdir -p "$USER_SETTINGS_DIR"
    mkdir -p "$EXTENSIONS_DIR"
    
    # Inject the settings.json.
    # We write it to a file rather than symlinking it from the Nix store. 
    # If we symlinked it, it would be read-only, which causes VS Code to 
    # throw errors when it tries to write internal UI state to the file.
    # This approach enforces the Nix config on every launch while remaining writable.
    cat > "$USER_SETTINGS_DIR/settings.json" << 'EOF'
    ${settingsJson}
    EOF
    
    # Prepend our required dependencies to the PATH
    export PATH="${pkgs.lib.makeBinPath runtimeDeps}:$PATH"

    # Copy the external cheatsheet into the data directory.
    # We use `cat` instead of `cp` to ensure the resulting file is writable, 
    # preventing VS Code from complaining about read-only Nix store paths.
    CHEATSHEET="$VSCODE_DATA_DIR/LaTeX_Studio_Cheatsheet.md"
    cat ${./cheatsheet.md} > "$CHEATSHEET"

    # INSTALL COPILOT DYNAMICALLY (MUTABLE)
    # We check if it's already installed to avoid delaying the startup every time.
    if [ ! -d "$EXTENSIONS_DIR/github.copilot-"* ]; then
        echo "Installing GitHub Copilot..."
        ${vscodeWithLatex}/bin/code --user-data-dir "$VSCODE_DATA_DIR" --extensions-dir "$EXTENSIONS_DIR" --install-extension GitHub.copilot --force
        ${vscodeWithLatex}/bin/code --user-data-dir "$VSCODE_DATA_DIR" --extensions-dir "$EXTENSIONS_DIR" --install-extension GitHub.copilot-chat --force
    fi
    
    # Launch the isolated instance using --user-data-dir.
    # This prevents IPC conflicts with your standard VS Code.
    # LAUNCH LOGIC:
    # If the user launched the app from the KDE menu (0 arguments), open the cheatsheet.
    # Otherwise, pass the arguments (e.g., the clicked .tex file) directly to VS Code.
    if [ $# -eq 0 ]; then
      exec ${vscodeWithLatex}/bin/code --user-data-dir "$VSCODE_DATA_DIR" --extensions-dir "$EXTENSIONS_DIR" "$CHEATSHEET"
    else
      exec ${vscodeWithLatex}/bin/code --user-data-dir "$VSCODE_DATA_DIR" --extensions-dir "$EXTENSIONS_DIR" "$@"
    fi
  '';

  # 5. Create the Desktop entry for KDE/GNOME
  desktopItem = pkgs.makeDesktopItem {
    name = "latex-vscode";
    desktopName = "LaTeX IDE (VS Code)";
    comment = "Robust local LaTeX environment powered by Tectonic";
    icon = "vscode";
    exec = "${wrapperBin}/bin/latex-vscode %F";
    categories = [ "Development" "TextEditor" "Utility" ];
    startupWMClass = "Code";
    terminal = false;
  };

in
# 6. Combine the binary and the desktop item into the final package
pkgs.symlinkJoin {
  name = "latex-vscode-app";
  paths = [ 
    wrapperBin 
    desktopItem 
  ];
  meta = with pkgs.lib; {
    description = "Isolated VS Code configured for LaTeX with Tectonic";
    mainProgram = "latex-vscode";
    platforms = platforms.all;
  };
}
