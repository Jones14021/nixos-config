{ ... }:

let
  # The *-cli commands are Flatpak wrappers from modules/flatpak.nix; ports must
  # match the <APP>_CONTROL_PORT permissions in unmanagedFlatpakApps there.
  artcraftMcp = command: {
    type = "local";
    inherit command;
    enabled = true;
  };
in
{
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    mcp = {
      wordcraft = artcraftMcp [ "wordcraft-cli" "mcp" "--connect" "127.0.0.1:7981" ];
      # --lazy lets the bridge start before the GUI runs.
      cadcraft = artcraftMcp [ "cadcraft-cli" "mcp" "--connect" "127.0.0.1:7982" "--lazy" ];
      deckcraft = artcraftMcp [ "deckcraft-cli" "mcp" "--connect" "127.0.0.1:7983" ];
      gridcraft = artcraftMcp [ "gridcraft-cli" "mcp" "--connect" "127.0.0.1:7984" ];
      photocraft = artcraftMcp [ "photocraft-cli" "mcp" "--bridge" "127.0.0.1:7985" ];
      soundcraft = artcraftMcp [ "soundcraft-cli" "mcp" "--connect" "127.0.0.1:7986" ];
    };
  };
}