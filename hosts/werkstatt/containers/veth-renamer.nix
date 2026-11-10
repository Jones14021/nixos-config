{ buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "veth-renamer";
  version = "0.1.8";

  src = fetchFromGitHub {
    owner = "mayberryjp";
    repo = "veth-rename";
    rev = "v${version}";
    hash = "sha256-IC3wvIDd+zL12PG8pEMUSlsfW9odeMnP4tZbdw9mL+Q=";
  };

  vendorHash = null;

  postInstall = ''
    mv "$out/bin/veth-rename" "$out/bin/veth-renamer"
  '';
}