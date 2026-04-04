# ========================================================================================
# HOW THIS WORKS & PHILOSOPHY
# ========================================================================================
# This module declaratively creates network mounts using the kernel's native `cifs` module
# combined with systemd automounts (`x-systemd.automount`). 
#
# Why is this stable compared to gvfs + bash connection watcher?
# 1. On-Demand Mounting: The share isn't actually mounted at boot. Systemd intercepts
#    the first read/write attempt to the folder and mounts it instantly in the background.
# 2. Native Timeouts: If your VPN drops, `gvfs` and file managers often freeze indefinitely 
#    waiting for IO. `x-systemd.device-timeout=5s` tells the kernel to aggressively kill 
#    the connection attempt if the network is down, preventing your system from hanging.
# 3. Auto-Cleanup: `x-systemd.idle-timeout=60` safely unmounts the share after 60 seconds
#    of inactivity, meaning it won't complain when you suspend the laptop or change networks.
#
# CREDENTIALS FILE FORMAT:
# You must manually place credential files inside ~/shares/credentials/<mountName>.creds
# The file must contain exactly:
#   username=your_username
#   password=YOUR_STRONG_PASSWORD
#   domain=your_domain (optional)
#
# Note: The kernel mounts these globally, so systemd runs the mount unit as root. Root 
# reads the credentials from your home folder, but ownership is securely passed back to 
# your user via the `uid` and `gid` CIFS parameters.
# ========================================================================================

{ config, pkgs, lib, ... }:

let
  # Define all your CIFS mounts here. Adding a new one requires zero Home Manager changes.
  # The system will automatically create ~/shares/credentials for whatever `sysUser` you define.
  cifsMounts = {
    othHome = {
      device = "//fs.hs-regensburg.de/storage/Home/hoj43157";
      folderName = "othHome";  
      sysUser = "jonas"; # The NixOS user who will own the mount
    };

    # Example of how easily you can add another mount:
    # homeNas = {
    #   device = "//nas.local/backups/nixos";
    #   folderName = "homeNas";
    #   sysUser = "jonas";
    # };
  };

in {
  environment.systemPackages = [ pkgs.cifs-utils ];

  systemd.tmpfiles.rules = 
    # Force the base shares folder to be user-owned to prevent unsafe path transition errors
    lib.unique (lib.mapAttrsToList (name: m: let
      userGroup = config.users.users.${m.sysUser}.group;
    in
      "d /home/${m.sysUser}/shares 0755 ${m.sysUser} ${userGroup} - -"
    ) cifsMounts)

    ++

    # Automatically create the credentials directories for all users dynamically
    # lib.unique ensures that if 'sysUser' has multiple mounts, the directory rule is only created once.
    lib.unique (lib.mapAttrsToList (name: m: let
      userGroup = config.users.users.${m.sysUser}.group;
    in
      "d /home/${m.sysUser}/shares/credentials 0700 ${m.sysUser} ${userGroup} - -"
    ) cifsMounts)

    ++

    # Automatically provision the default `.creds` template file if missing
    (lib.mapAttrsToList (name: m: let
      userGroup = config.users.users.${m.sysUser}.group;
      
      # We define the template file in the Nix store. 
      # It comes pre-filled with the sysUser as a hint.
      # https://man.archlinux.org/man/mount.cifs.8.en
      defaultCreds = pkgs.writeText "${name}-default.creds" ''
        username=${m.sysUser}
        password=YOUR_STRONG_PASSWORD
        domain=WORKGROUP
      '';
    in
      # The 'C' directive copies the file from the Nix store only if it doesn't already exist.
      # It securely sets the permissions to 0600 so only the user (and root) can read the password.
      "C /home/${m.sysUser}/shares/credentials/${name}.creds 0600 ${m.sysUser} ${userGroup} - ${defaultCreds}"
    ) cifsMounts)
  ;

  # Generate systemd mount and automount units dynamically
  fileSystems = lib.mapAttrs' (name: m: let
    userGroup = config.users.users.${m.sysUser}.group;
    credsDir = "/home/${m.sysUser}/shares/credentials";
    mountPoint = "/home/${m.sysUser}/shares/${m.folderName}";
  in lib.nameValuePair mountPoint {
    device = m.device;
    fsType = "cifs";
    options = let
      # The magic options that make this robust against VPN drops and suspends
      automount_opts = "x-systemd.automount,noauto,x-systemd.idle-timeout=60,x-systemd.device-timeout=5s,x-systemd.mount-timeout=5s";
    in [
      "${automount_opts}"
      "credentials=${credsDir}/${name}.creds"
      
      # CIFS accepts string usernames natively! 
      # The kernel will resolve 'sysUser' and the correct primary group to numerical IDs during the mount.
      "uid=${m.sysUser}"
      "gid=${userGroup}"
      
      "dir_mode=0755"
      "file_mode=0755"
      "vers=3.0"
    ];
  }) cifsMounts;
}
