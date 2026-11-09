{ lib, pkgs, ... }:

let
  # One-time setup (use the physical console; networking may briefly drop):
  # 1. Set lanInterface below to the host's wired LAN interface, visible with
  #    `ip -br link`. Wi-Fi client interfaces generally cannot be bridged.
  # 2. Rebuild: NetworkManager creates br0 and attaches the wired interface.
  #    The host receives its LAN address on br0. Check `ip address show br0`
  #    and `bridge link`; an existing competing connection may need disabling.
  # 3. If no disk exists, the VM service downloads and verifies the latest
  #    stable Home Assistant OS KVM image and boots its setup assistant.
  #    To migrate an existing VM instead, place its disk at the path below
  #    before starting this service; existing disks are never replaced.
  # 4. Reserve the desired IP for the libvirt-assigned MAC on the LAN DHCP
  #    server, or configure it inside Home Assistant OS. Find the MAC using
  #    `virsh -c qemu:///system domiflist home-assistant --inactive`.
  # 5. Home Assistant uses its own Tailscale installation, not host Serve.
  #    See migration/README.md for migration and recovery instructions.

  # Wired interface to attach to br0. Set this before enabling the VM.
  lanInterface = null;
  # Resources assigned to Home Assistant OS, independent of its own updates.
  guestCpus = 2;
  guestMemoryMiB = 2048;
  # The guest disk and UEFI variables remain writable outside the Nix store.
  base = "/home/jonas/services/home-assistant";
  provision = pkgs.writeShellScript "home-assistant-provision" (builtins.readFile ./home-assistant-provision.sh);

  # The VM definition, not the Home Assistant OS release, is managed by Nix.
  # Adjust RAM, CPUs, disk bus and passthrough devices for an imported VM.
  # Libvirt assigns the MAC automatically; the service preserves it on updates.
  domain = pkgs.writeText "werkstatt-home-assistant.xml" ''
    <domain type='kvm'>
      <name>home-assistant</name>
      <memory unit='MiB'>${toString guestMemoryMiB}</memory>
      <vcpu>${toString guestCpus}</vcpu>
      <os firmware='efi'>
        <type arch='x86_64' machine='q35'>hvm</type>
        <firmware><feature enabled='no' name='secure-boot'/></firmware>
        <!-- Writable firmware variables are kept with the guest disk. -->
        <nvram>${base}/nvram.fd</nvram>
      </os>
      <features><acpi/><apic/></features>
      <cpu mode='host-passthrough'/>
      <devices>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2'/>
          <source file='${base}/home-assistant.qcow2'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <interface type='bridge'>
          <source bridge='br0'/>
          <model type='virtio'/>
        </interface>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
        </channel>
        <!-- The local console is available to virt-manager, not the LAN. -->
        <graphics type='vnc' autoport='yes' listen='127.0.0.1'/>
        <video><model type='vga'/></video>
      </devices>
    </domain>
  '';
in
{
  # Ask the guest to shut down cleanly rather than saving VM memory outside
  # the home tree. Startup is controlled by the unit below.
  virtualisation.libvirtd.onShutdown = "shutdown";
  virtualisation.libvirtd.onBoot = "ignore";
  environment.etc."werkstatt/home-assistant.xml".source = domain;

  # Create bridge profiles only after the actual wired interface is selected.
  networking.networkmanager.ensureProfiles.profiles = lib.mkIf (lanInterface != null) {
    werkstatt-bridge = {
      connection = { id = "werkstatt-bridge"; type = "bridge"; interface-name = "br0"; autoconnect = true; autoconnect-ports = 1; };
      bridge.stp = false;
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
    werkstatt-bridge-port = {
      connection = { id = "werkstatt-bridge-port"; type = "ethernet"; interface-name = lanInterface; master = "br0"; slave-type = "bridge"; autoconnect = true; };
      ethernet = { };
    };
  };

  # Provision only when the disk does not exist, then define and start the VM.
  # A configured bridge is required; libvirt manages the guest after startup.
  systemd.services.werkstatt-home-assistant = {
    description = "Define and start the Home Assistant OS virtual machine";
    after = [ "libvirtd.service" "NetworkManager-ensure-profiles.service" "network-online.target" ];
    requires = [ "libvirtd.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/class/net/br0";
    unitConfig.RequiresMountsFor = [ base ];
    path = [ pkgs.libvirt pkgs.curl pkgs.jq pkgs.xz pkgs.qemu_kvm pkgs.xmlstarlet ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${provision} ${lib.escapeShellArg "${base}/home-assistant.qcow2"}

      if virsh -c qemu:///system dominfo home-assistant > /dev/null 2>&1; then
        temporary=$(mktemp -d ${lib.escapeShellArg "${base}/.haos-define.XXXXXXXX"})
        trap 'rm -rf -- "$temporary"' EXIT
        virsh -c qemu:///system dumpxml --inactive home-assistant > "$temporary/current.xml"
        uuid=$(xmlstarlet sel -t -v 'string(/domain/uuid)' "$temporary/current.xml")
        mac=$(xmlstarlet sel -t -v 'string(/domain/devices/interface[1]/mac/@address)' "$temporary/current.xml")
        if [[ ! "$uuid" =~ ^[0-9a-fA-F-]{36}$ || ! "$mac" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
          echo "Could not preserve the existing Home Assistant VM identity" >&2
          exit 1
        fi
        xmlstarlet ed \
          -a '/domain/name' -t elem -n uuid -v "$uuid" \
          -s '/domain/devices/interface[1]' -t elem -n mac -v "" \
          -s '/domain/devices/interface[1]/mac' -t attr -n address -v "$mac" \
          ${domain} > "$temporary/updated.xml"
        virsh -c qemu:///system define "$temporary/updated.xml"
      else
        virsh -c qemu:///system define ${domain}
      fi
      if ! virsh -c qemu:///system domstate home-assistant | grep -q '^running'; then
        virsh -c qemu:///system start home-assistant
      fi
    '';
  };

}