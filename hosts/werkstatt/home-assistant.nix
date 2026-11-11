{ lib, pkgs, ... }:

let
  # See configuration.nix for the shared LAN bridge.
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
      <on_crash>restart</on_crash>
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

  # Provision only when the disk does not exist, then define and start the VM.
  # A configured bridge is required; libvirt manages the guest after startup.
  systemd.services.werkstatt-home-assistant = {
    description = "Define and start the Home Assistant OS virtual machine";
    after = [ "libvirtd.service" "werkstatt-lan-bridge.service" "network-online.target" ];
    requires = [ "libvirtd.service" "werkstatt-lan-bridge.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
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

  # A dependency failure prevents systemd from starting the oneshot at all, so
  # retry it independently and also recover a guest that later stops.
  systemd.services.werkstatt-home-assistant-recovery = {
    description = "Recover the Home Assistant VM when it is stopped";
    path = [ pkgs.libvirt pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      systemctl start werkstatt-lan-bridge.service
      systemctl start werkstatt-home-assistant.service

      state="$(virsh -c qemu:///system domstate home-assistant)"
      case "$state" in
        "shut off"|crashed)
          virsh -c qemu:///system start home-assistant
          ;;
      esac
    '';
  };

  systemd.timers.werkstatt-home-assistant-recovery = {
    description = "Periodically retry Home Assistant VM startup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitInactiveSec = "1min";
      AccuracySec = "5s";
    };
  };

}