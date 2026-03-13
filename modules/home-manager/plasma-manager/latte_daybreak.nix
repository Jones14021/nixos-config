# =========================================================================
# Configuration Name: Latte Daybreak
# Description: A light, soothing pastel and flat design setup for KDE 
#              Plasma 6 on NixOS, featuring the Catppuccin Latte theme.
# =========================================================================

{ pkgs, ... }:

{
  # 1. Install required packages for the light theme
  home.packages = with pkgs; [
    catppuccin-kde                    # Provides the Catppuccin Global Theme & Color Schemes
    catppuccin-kvantum                # Kvantum themes for Catppuccin (includes Latte)
    kdePackages.qtstyleplugin-kvantum # Kvantum engine for Plasma 6
    papirus-icon-theme                # Flat design icons (includes the light variant)
    catppuccin-cursors.latteBlue      # Matching light cursor theme with blue accent [web:50]
  ];

  # 2. Plasma-Manager configuration
  programs.plasma = {

    workspace = {
      # Apply the global Catppuccin Latte (Light) theme
      lookAndFeel = "Catppuccin-Latte";
      
      # Apply the specific color scheme
      colorScheme = "CatppuccinLatte";
      
      # Use the light variant of the Papirus icon theme [web:54]
      iconTheme = "Papirus-Light";
      
      # Set the cursor theme and size
      cursor = {
        theme = "catppuccin-latte-blue-cursors";
        size = 24;
      };
    };

    # 3. Force Kvantum as the Application Style
    # This ensures flat buttons, modern menus, and proper transparency
    configFile."kdeglobals"."KDE"."widgetStyle" = "kvantum";
  };

  # 4. Configure Kvantum to use the Catppuccin Latte theme
  xdg.configFile."Kvantum/kvantum.kvconfig".text = ''
    [General]
    theme=catppuccin-latte-blue
  '';
}
