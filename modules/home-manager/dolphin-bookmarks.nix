{ config, pkgs, lib, ... }:

{
  # Generate Dolphin Bookmarks dynamically for anything in ~/shares/
  # see ./modules/mounts.nix for how the CIFS mounts are set up and automatically created in ~/shares/
  home.activation.addDolphinBookmarks = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PLACES_FILE="$HOME/.local/share/user-places.xbel"
    SHARES_DIR="$HOME/shares"
    
    # Initialize basic xbel file if KDE hasn't created one yet
    if [ ! -f "$PLACES_FILE" ]; then
      mkdir -p "$HOME/.local/share"
      echo '<?xml version="1.0" encoding="UTF-8"?>' > "$PLACES_FILE"
      echo '<!DOCTYPE xbel>' >> "$PLACES_FILE"
      echo '<xbel xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks" xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info">' >> "$PLACES_FILE"
      echo '</xbel>' >> "$PLACES_FILE"
    fi

    # Loop through all actual folders in ~/shares/
    if [ -d "$SHARES_DIR" ]; then
      # Use ls -1 to get the names without running stat() on the directories!
      # This prevents systemd automounts from triggering during nixos-rebuild.
      for folder_name in $(ls -1 "$SHARES_DIR" 2>/dev/null); do
        [ "$folder_name" = "credentials" ] && continue

        # Format exact URI string (strip trailing slash)
        URI="file://$SHARES_DIR/$folder_name"
        URI=''${URI%/}
        
        # Inject if missing
        if ! grep -q "$URI" "$PLACES_FILE"; then
          sed -i '/<\/xbel>/i \
          <bookmark href="'"$URI"'">\n\
            <title>'$folder_name'</title>\n\
            <info>\n\
              <metadata owner="http://freedesktop.org">\n\
                <bookmark:icon name="network-server"/>\n\
              </metadata>\n\
              <metadata owner="http://www.kde.org">\n\
                <ID>share-'$folder_name'</ID>\n\
                <isSystemItem>false</isSystemItem>\n\
              </metadata>\n\
            </info>\n\
          </bookmark>' "$PLACES_FILE"
        fi
      done
    fi
  '';
}
