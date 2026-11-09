{ lib, pkgs, ... }:

let
  # One-time setup (use the physical console; networking may briefly drop):
  # 1. Set lanInterface below to the host's wired LAN interface, visible with
  #    `ip -br link`. Wi-Fi client interfaces generally cannot be bridged.
  # 2. Rebuild: NetworkManager creates br0 and attaches the wired interface.
  #    The host receives its LAN address on br0. Check `ip address show br0`
  #    and `bridge link`; an existing competing connection may need disabling.
  # 3. Copy the old VM disk to base/home-assistant.qcow2 and check its firmware,
  #    MAC, disk bus and passthrough devices. Back up disk and UEFI state first.
  # 4. Reserve the desired IP for guestMac on the LAN DHCP server, or configure
  #    it inside Home Assistant OS. A bridge cannot assign the guest's IP.
  # 5. Create base/.ready after migration and start werkstatt-home-assistant.
  #    Home Assistant uses its own Tailscale installation, not host Serve.
  #    See migration/README.md for detailed checks and rollback instructions.

  # Wired interface to attach to br0. Set this before enabling the VM.
  lanInterface = null;
  # Resources assigned to Home Assistant OS, independent of its own updates.
  guestCpus = 2;
  guestMemoryMiB = 4096;
  # Stable guest MAC, also used for any LAN DHCP reservation.
  guestMac = "52:54:00:77:65:72";
  # The guest disk and UEFI variables remain writable outside the Nix store.
  base = "/home/jonas/services/home-assistant";

  # The VM definition, not the Home Assistant OS release, is managed by Nix.
  # The imported qcow2 disk must already contain a compatible UEFI install.
  # Adjust RAM, CPUs, MAC, disk bus and passthrough devices for the old VM.
  domain = pkgs.writeText "werkstatt-home-assistant.xml" ''
    <domain type='kvm'>
      <name>home-assistant</name>
      <memory unit='MiB'>${toString guestMemoryMiB}</memory>
      <vcpu>${toString guestCpus}</vcpu>
      <os firmware='efi'>
        <type arch='x86_64' machine='q35'>hvm</type>
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
          <mac address='${guestMac}'/>
          <source bridge='br0'/>
          <model type='virtio'/>
        </interface>
        <!-- The local console is available to virt-manager, not the LAN. -->
        <graphics type='vnc' autoport='yes' listen='127.0.0.1'/>
        <video><model type='vga'/></video>
      </devices>
    </domain>
  '';
in
{
  # Ask the guest to shut down cleanly rather than saving VM memory outside
  # the home tree. Startup is controlled by the readiness-gated unit below.
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

  # Define the VM at boot, then start it if it is stopped.
  # The readiness marker prevents a newly installed host from booting an
  # empty or partially copied disk. Libvirt manages the guest after startup.
  systemd.services.werkstatt-home-assistant = {
    description = "Define and start the Home Assistant OS virtual machine";
    after = [ "libvirtd.service" "NetworkManager-ensure-profiles.service" "network-online.target" ];
    requires = [ "libvirtd.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = [ "${base}/.ready" "${base}/home-assistant.qcow2" "/sys/class/net/br0" ];
    unitConfig.RequiresMountsFor = [ base ];
    path = [ pkgs.libvirt ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      virsh -c qemu:///system define ${domain}
      if ! virsh -c qemu:///system domstate home-assistant | grep -q '^running'; then
        virsh -c qemu:///system start home-assistant
      fi
    '';
  };

}