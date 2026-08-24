{ pkgs, ... }:

{
  # Enable the legacy X server infrastructure.
  # Plasma can still run as a Wayland session; this is often retained for
  # X11 compatibility and to make an X11 Plasma session available in SDDM.
  services.xserver.enable = true;

  # Enable SDDM, KDE Plasma's usual display/login manager.
  services.displayManager.sddm.enable = true;

  # Enable KDE Plasma 6.
  services.desktopManager.plasma6.enable = true;

  # Turn Num Lock on automatically at the SDDM login screen.
  services.displayManager.sddm.autoNumlock = true;

  # Configure the graphical-session keyboard layout.
  # "de" selects the German keyboard layout; empty variant means default DE layout.
  services.xserver.xkb = {
    layout = "de";
    variant = "";
  };
  # Configure the keyboard layout used on Linux virtual terminals (TTYs).
  console.keyMap = "de";

  # Enable XDG Desktop Portal support system-wide.
  # Portals provide a standard D-Bus interface for desktop integrations such as
  # file pickers, screen sharing, camera permissions, and other sandboxed-app APIs.
  xdg.portal = {
    # Install and enable the xdg-desktop-portal service.
    enable = true;

    # Prefer portal-based handling when programs use `xdg-open`.
    # This helps desktop applications use Plasma's file/application chooser.
    xdgOpenUsePortal = true;

    # Install portal backend implementations.
    extraPortals = [
      # Native Plasma/KDE backend.
      # This is the important backend for a Plasma Wayland session and should
      # handle KDE-specific portal requests.
      pkgs.kdePackages.xdg-desktop-portal-kde

      # GTK backend as a fallback for portal interfaces that KDE does not provide
      # or for GTK-oriented applications.
      pkgs.xdg-desktop-portal-gtk
    ];

    # Define portal backend selection for a KDE session.
    config = {
      kde = {
        # Use the KDE backend first; fall back to GTK when needed.
        # The ordering matters: KDE should be the preferred implementation in Plasma.
        default = [ "kde" "gtk" ];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    kdePackages.kate
    kdePackages.isoimagewriter
    kdePackages.partitionmanager
    kdePackages.kcalc
  ];
}
