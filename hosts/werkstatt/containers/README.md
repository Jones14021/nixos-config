# Werkstatt Compose projects

Each YAML file is an ordinary Docker Compose project and is the source of truth
for its containers. Nix does not generate their definitions: `default.nix`
installs them under `/etc/werkstatt/compose/` and manages their systemd units.
Edit the YAML in this repository and rebuild; `/etc` points into the Nix store.
The fixed project names `werkstatt-<file-name>` preserve Docker network and
container names. When using another Compose manager, use the same project name
and host paths; otherwise the network-specific veth labels will not match.

Images generally use version tags. Review upgrades and backups
explicitly. Paths, ports, non-secret settings and bridge names are intentionally host-specific.
Docker-published ports can bypass the NixOS firewall. Secrets stay outside the
Nix store in `/home/jonas/services/secrets/*.env`; Compose's `format: raw`
prevents interpolation of their contents and requires a recent Compose version.
NEUGIER uses its original Compose environment format in the protected
`/home/jonas/services/neugier/neugier.env` file instead. Its Tailscale state is
stored alongside its data and retains its separate identity. Stop the original
NEUGIER node before starting it on Werkstatt.
The long-running units require their `/home/jonas/services/<project>/.ready`
marker and start and stop the whole project. They are not health checks. The
Bitwarden backup is manual, requires its own marker and the NAS mount, and uses
`compose run --rm`; it does not start on boot. A changed unit can restart during
`nixos-rebuild switch`, interrupting its project and recreating containers. An
unchanged rebuild does not necessarily restart it.

## Interface names

The Compose network bridge names are explicit. Each service also has a unique
`host-veth-name.<actual Docker network name>` label, kept within the Linux
15-byte primary interface-name limit. The network-specific label leaves any
other attachments unmanaged. Update its suffix if the Compose project or Docker
network name changes. Avoid duplicate names across the host; replicas need
distinct labels.

The pinned [veth-renamer](https://github.com/mayberryjp/veth-rename) runs as a
host systemd service with `--mode=primary-repair`, so Mission Center can display
the actual kernel interface names. It listens to Docker events and periodically
rescans, including after containers are recreated. It only acts on labeled
endpoints, including any independently labeled containers on the same host.
vnStat integration is disabled. A rename briefly takes the verified host veth
down. Ordinary failures are rolled back, but abrupt termination, host failure,
and concurrent network changes cannot be made atomic; another interface
manager must not rename the same links. The daemon runs as root with network and
namespace capabilities and access to the root-equivalent Docker socket.

For inspection and a read-only preview:

```sh
sudo systemctl status veth-renamer
sudo journalctl -u veth-renamer -n 100
sudo cat /run/veth-renamer/mappings.json
sudo veth-renamer --once --dry-run --mode=primary-repair --vnstat=off
ip -br link
```

The snapshot contains container names and addresses and is restricted to root.
Failures and collisions are retried and appear in the journal and snapshot; a
running service does not guarantee every name was applied. Stopping the daemon
does not undo existing names. Test changes with disposable containers first;
upstream unit tests do not establish live Docker/kernel behavior. Removing or
recreating a container also removes its host veth and its name.
