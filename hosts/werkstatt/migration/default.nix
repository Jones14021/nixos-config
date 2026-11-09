{ pkgs, ... }:

{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "werkstatt-migrate";
      runtimeInputs = with pkgs; [ python3 docker docker-compose cifs-utils util-linux coreutils gnutar systemd ];
      text = ''
        exec ${pkgs.python3}/bin/python3 ${./migrate.py} "$@"
      '';
    })
  ];
}