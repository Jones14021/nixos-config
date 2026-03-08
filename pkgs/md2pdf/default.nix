{ lib, stdenv, makeWrapper, pandoc, typst, python3 }:

stdenv.mkDerivation {
  pname = "md2pdf";
  version = "1.0.0";

  # Use the current directory as the source for the build
  src = ./.;

  # makeWrapper allows us to securely inject runtime dependencies into the PATH
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    # Create the target binary directory in the Nix store
    mkdir -p $out/bin
    
    # Copy the scripts (and drop the .sh extension for the main CLI command)
    cp md2pdf.sh $out/bin/md2pdf
    cp fix_lists.py $out/bin/fix_lists.py
    
    # Ensure both scripts are executable
    chmod +x $out/bin/md2pdf $out/bin/fix_lists.py
    
    # Patch the relative Python script call in the Bash script.
    # This dynamically replaces './fix_lists.py' with the absolute, immutable path in the Nix store.
    sed -i "s|\./fix_lists\.py|$out/bin/fix_lists.py|g" $out/bin/md2pdf
    
    # Wrap the bash script to ensure pandoc, typst, and python3 
    # are ALWAYS found at runtime, regardless of the user's local environment.
    wrapProgram $out/bin/md2pdf \
      --prefix PATH : ${lib.makeBinPath [ pandoc typst python3 ]}
  '';

  meta = with lib; {
    description = "Converts Markdown to beautiful PDFs using Pandoc and Typst";
    mainProgram = "md2pdf";
    platforms = platforms.all;
  };
}
