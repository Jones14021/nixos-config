# Werkstatt migration guide

This guide is for the future migration. The investigation did not stop or
modify the source services. Commands that stop services or copy data are for
you to run during a planned maintenance window. Keep the old machine and
independent backups until every restore has been verified.

## Two-run migration

The script in this directory backs up on `ubuntu2004` and restores on
`werkstatt`, selecting the mode from the hostname. It is not being run by the
configuration itself. This is a disruptive maintenance operation: choose a
window and use a local console or persistent `tmux` session.

1. Make an independently restorable backup of the old host and both VMs first,
   especially Home Assistant. Wake the Synology and ensure the account has
   access to `shared_common` and `workouts`. Restrict access to
   `shared_common/services_migration`: snapshots contain plaintext passwords,
   private keys, databases, container filesystems and personal files.
2. Before formatting anything, copy `migrate.py` to Ubuntu. For example, from
   the machine with this repository:

   ```sh
   scp hosts/werkstatt/migration/migrate.py ubuntu@ubuntu2004:/home/ubuntu/werkstatt-migrate.py
   ```

3. On **ubuntu2004**, close desktop applications, then run:

   ```sh
   sudo python3 /home/ubuntu/werkstatt-migrate.py
   ```

   Enter the Synology credentials directly when prompted. After the `STOP
   SERVICES` confirmation, the script stops every running Docker container and
   the identified application services, including cron, native Gitea,
   Jellyfin and MariaDB. Docker itself, SSH, networking and Tailscale remain
   running so the backup and connection can continue. Other desktop processes
   are not automatically stopped. Services remain stopped after success or
   failure; do not resume writes and then assume the snapshot is current.
4. The script writes a new timestamped directory under
   `//10.0.2.200/shared_common/services_migration`, never replacing an older
   snapshot. It checks available space, archives local Docker volumes, image
   and container filesystems, application data, configuration and home files,
   then verifies checksums by rereading every file. A snapshot is complete
   only when `COMPLETE` exists and the script reports success. Incomplete
   directories are retained for diagnosis and never selected for restore.
5. Before formatting the old machine, verify the `COMPLETE` marker and a
   second independent backup, and test a restore. The script cannot guarantee
   recovery from NAS failure, unseen external mounts, filesystem errors or an
   untested application upgrade. Do **not** format the old host just because
   the command exited successfully. The separate Home Assistant VM, NAS media
   and external Docker volumes are **not** copied; the script lists external
   volumes. Back up the Home Assistant disk and UEFI state yourself.
6. Install NixOS and activate the `werkstatt` configuration as described
   below, including the actual hardware configuration and wired interface.
   With the NAS running, on **werkstatt** run:

   ```sh
   sudo /run/current-system/sw/bin/werkstatt-migrate
   ```

   Enter NAS credentials, confirm `RESTORE`, then review the selected snapshot.
   The command verifies checksums, makes local copies, extracts into a private
   staging directory, reconstructs secrets and permissions, validates Compose
   and refuses to overwrite existing files or symlinks. `INSTALL` installs the
   staged files; `START SERVICES` creates readiness markers and starts the
   selected services. If Docker already has images, the script does not load
   the saved tags over them. Even after loading saved images, Compose may need
   registry access to resolve pinned digests. Tailscale enrollment is offered
   separately. Bitwarden backup
   remains a manual one-shot and Home Assistant remains your separate migration.
7. Test logins, Git over both transports, media, recipes, Guacamole, Firefly,
   NAS access and backups. Starting native Gitea upgrades a **copy** of the
   database from 1.21.3 to 1.27.3; its success and old encrypted credentials
   must be verified. The untouched NAS archives remain your rollback source.

To select an older complete snapshot without deleting the latest one:

```sh
sudo /run/current-system/sw/bin/werkstatt-migrate restore --snapshot <snapshot-directory-name>
```

The restore preserves a private `.migration-restore-*` directory for recovery.
If interrupted or if a service fails, inspect the printed directory and
journals. Do not delete the NAS snapshot or rerun over partial destination
files: the script intentionally refuses conflicts. Remove or relocate only
after you have verified what was installed and have a separate backup.

If installation finished but service activation was declined or interrupted,
resume just that step on `werkstatt`:

```sh
sudo /run/current-system/sw/bin/werkstatt-migrate start
```

Confirm `START SERVICES` when prompted. This checks restored directories,
secrets and Compose configuration, preserves existing `.ready` markers, and
starts the selected services without mounting or copying the migration snapshot.
Jellyfin itself still requires the workouts NAS share to be available. The
Bitwarden backup stays a manual one-shot. The command checks Docker network
attachments, published ports and native service listeners, but applications
can still be starting or fail later. Check health and logins afterward.

The NAS username/password entered on the new host are also installed as
`nas.creds` if that file does not already exist. An existing regular file is
preserved. The account must have the share permissions described below; if it
does not, create appropriate credentials before starting dependent services.
The script preserves the original Gitea fallback key when the old config has
an empty `SECRET_KEY`, rather than generating a different key. The fallback is
publicly known and should be treated as weak; don't change it without a
supported migration of existing encrypted Gitea data.

## Inventory and scope

The source is `ubuntu@ubuntu2004`, historically `10.0.2.135`.

| Application | Source | Target and original port |
| --- | --- | --- |
| Gitea | Docker `gitea`, 1.21.3, SQLite | Native Gitea 1.27.3, HTTP 5000, SSH 2221 |
| Jellyfin | Native service, server 10.10.7 | Native Jellyfin, HTTP 8096 |
| Norish | App, PostgreSQL 17, Redis, Obscura | Compose, HTTP 9901 |
| Nginx Proxy Manager | Docker `nginx-proxy-manager-app-1` | Compose, HTTP 80, admin 81, HTTPS 443 |
| Guacamole | Docker `Guacamole`, stopped | Compose, HTTP 9800 |
| Firefly III | App, MariaDB, Redis, cron, stopped | Compose, HTTP 6182 |
| Bitwarden backup | `bitwarden_backup`, stopped one-shot | Manually started Compose job |
| Tailscale | Ubuntu node | New, separately enrolled host node |
| Home Assistant OS | Separate VM on old host | Bridged libvirt VM; guest manages its OS and Tailscale |
| Monitoring | Portainer | Native Netdata, tailnet HTTPS 19999 |

The separate native Gitea instance on Ubuntu is **not** selected. Neither are
JupyterLab, File Browser, OpenVPN, No-IP, ownCloud, Thunderbird, Jenkins,
Headscale, WireGuard UI, Webmap, Anvil, Snapmaker server or TFTP. Portainer
is not migrated. File Browser exposed volumes of unselected stacks; do not
assume those volumes are included.

The source proxy database contains one disabled ownCloud route. The Synology
NAS at `10.0.2.200` is often powered down. The source Jellyfin workouts share
was unmounted during investigation; its library reported `/mnt/nas` inaccessible.
The new host mounts the share on demand and preserves that library path.

## Before installing

1. Inventory hardware, storage size, Ethernet interface, firmware mode and
   USB devices used by Home Assistant. Check KVM support and allow enough RAM
   for Plasma, Docker, Jellyfin and the VM concurrently.
2. Obtain and test independent, restorable backups of both old VMs, Docker
   volumes, proxy certificates, databases and configurations. Preserve the old
   Home Assistant VM disk and UEFI variables separately.
3. Use a wired LAN connection for the bridge; ordinary Wi-Fi client links
   generally cannot provide transparent bridging. Plan a physical-console
   session in case networking drops. Record host IPs, gateway, DNS, router
   forwards, switch restrictions and Tailscale access policies.
4. Reserve a different IP for the new host during testing. The guest should
   eventually use `10.0.2.136`; ensure the address is not in use and never run
   old and new Home Assistant instances simultaneously.
5. Review the security section. Docker-published ports can bypass the NixOS
   firewall and the source Gitea configuration allows registration.

## Install and activate

1. Install x86-64 NixOS manually in UEFI mode, using a filesystem layout with
   adequate space for `/home/jonas/services`. Set up the usual Jonas account.
   If `/home` is encrypted, arrange for boot-time unlocking; services cannot
   use a home directory only unlocked after desktop login.
2. Put this repository under `/home/jonas/nixos-config`. The generated
   `hosts/werkstatt/hardware-configuration.nix` describes the current
   installation. Check that its root, boot and swap UUIDs still match the
   machine, and regenerate it if the storage layout changes. Confirm the
   boot loader matches the actual firmware.
3. In `hosts/werkstatt/home-assistant.nix`, set `lanInterface` to the wired
   interface found with `ip -br link`. Adjust `guestCpus` and `guestMemoryMiB`.
   Libvirt assigns the guest MAC automatically and the service preserves it
   across redefinitions. Use the resulting address for any DHCP reservation.
   If importing the old VM disk, put it in place before enabling the bridge;
   otherwise the service automatically provisions a fresh Home Assistant OS.
4. Review the Gitea `ROOT_URL`, `DOMAIN` and SSH settings in `services.nix`,
   and Norish `AUTH_URL` and Firefly `APP_URL` in `containers.nix`. Ensure
   `werkstatt` resolves to the new host and choose a canonical URL for apps
   that depend on redirects; several different origins may not all work.
5. Git-backed flakes omit untracked files. Review and add the host files and
   hardware configuration to the Git index. Never add backups or secrets:

   ```sh
   cd /home/jonas/nixos-config
   git add flake.nix hosts/werkstatt
   sudo nixos-rebuild switch --flake .#werkstatt
   ```

   This stages files but does not commit them. Set a password and configure
   SSH keys for Jonas. Reboot and confirm Plasma, storage and networking.
6. Check `ip address show br0` and `bridge link`. The bridge should have the
   host's LAN address and the wired interface should be attached. A competing
   NetworkManager connection may need its autoconnect disabled. Check switch
   policies if multiple MAC addresses on one port are restricted. Keep console
   recovery available until the bridge has been tested.

Readiness markers prevent migrated services other than Home Assistant from
starting with empty data. Create each `.ready` only after restoring its data
and required secrets. Home Assistant starts automatically once `br0` exists.

## Tailscale and monitoring

1. Run `sudo tailscale up` on the new host and approve the new device. It is a
   new identity, not a copy of the old node. Enable MagicDNS and HTTPS
   certificates in the tailnet, and restrict access with ACLs/grants.
2. Run `sudo systemctl restart werkstatt-tailscale-serve`. Check
   `tailscale serve status` and `journalctl -u werkstatt-tailscale-serve -b`.
   The service retries if enrollment or HTTPS is not ready; it does not enable
   Funnel. HTTPS routes use the machine's Tailscale DNS name and separate
   listener ports: 10081 for proxy administration, 15000 for Gitea, 16182 for
   Firefly, 18096 for Jellyfin, 19800 for Guacamole, 19901 for Norish and
   19999 for Netdata. Their original LAN ports are unchanged. Gitea SSH on
   2221 is ordinary SSH. Home Assistant uses its own Tailscale.
3. Visit `https://<werkstatt-tailnet-name>:19999` for Netdata. Its Docker and
   explicitly configured systemd collectors show metrics and unit states.
   Compose services are oneshot supervisors: an active unit alone does not
   prove every container or endpoint is healthy. Check containers separately.

Serve routes persist in tailscaled state. Removing a port from Nix does not
remove its old route automatically. Inspect and remove obsolete routes
explicitly; `tailscale serve reset` deletes all Serve routes on that node.
The older configuration used ports 81, 5000, 6182, 8096, 9800 and 9901 for
Serve. Remove those old routes when migrating to the separate listener ports;
otherwise they can prevent the applications from binding their LAN ports.
Inspect `tailscale serve status --json` and `sudo ss -lntp` first, and
remove only old routes that belong to this configuration with
`tailscale serve --https=<old-port> off`. If listeners remain even though
the old routes are gone, investigate their owning process. Restarting
`tailscaled` disconnects Tailscale SSH, so do that only from a local console
or with another recovery path available.

## Secrets and staging

Application files, databases, credentials and certificates are not included
in Git or the Nix store. Create root-only environment files under
`/home/jonas/services/secrets`; use `sudoedit` and avoid values in shell
history or terminal recordings. The directory is created on activation.
Docker administrators, including members of the `docker` group, can inspect
container environment values despite the file permissions.

| File | Required private values |
| --- | --- |
| `norish.env` | `DATABASE_URL`, `MASTER_KEY`, `REDIS_URL`, `OBSCURA_ENDPOINT`, `OBSCURA_CDP_TOKEN` |
| `norish-db.env` | `POSTGRES_PASSWORD`, matching `DATABASE_URL` |
| `norish-obscura.env` | `OBSCURA_CDP_TOKEN`, matching the app |
| `guacamole.env` | `PUID` and `PGID` matching Jonas and the `users` group |
| `firefly.env` | Original `APP_KEY`, `DB_PASSWORD`, `REDIS_PASSWORD` if used, `STATIC_CRON_TOKEN`, mail credentials |
| `firefly-db.env` | Original `MYSQL_ROOT_PASSWORD` and `MYSQL_PASSWORD` for `fireflyuser` |
| `firefly-cron.env` | `STATIC_CRON_TOKEN`, identical to the app's token |
| `bitwarden-backup.env` | Bitwarden URL, user/client credentials and `BACKUP_PASSWORD` |

These Compose env files use `format: raw`: put one literal `NAME=value` per
line without shell quoting or interpolation; quotes are part of the value.
Check permissions with `sudo ls -l
/home/jonas/services/secrets`. The source Portainer definitions are inside
`/data/compose/11`, `/data/compose/30` and `/data/compose/33` in Portainer's
data volume. `docker inspect` can show values, so treat its output as sensitive.
Avoid logging `docker compose config`: it can print resolved secrets; use
`--no-env-resolution` for structural inspection.

The source Norish URL was `http://10.0.2.135:9901`, database `norish`.
Firefly used database host `firefly-db`, Redis host `firefly-redis`, database
`firefly`, user `fireflyuser`, and URL `http://10.0.2.135:6182`. Hostnames are
retained as Compose aliases. Non-secret values in Nix override env-file values;
edit Nix and rebuild to change them. Review the source's
`TRUSTED_PROXIES=**` instead of blindly trusting every proxy.

The source Docker volume metadata contained a CIFS password. Rotate that
credential and any other exposed credentials after migration. Do not put CIFS
passwords in Docker volume options or Nix configuration.

## Synology NAS access

The shared configuration in `nas.nix` mounts `//10.0.2.200/workouts` at
`/home/jonas/services/nas/workouts` and `//10.0.2.200/shared_common` at
`/home/jonas/services/nas/shared-common`. A bind mount exposes workouts at
the old `/mnt/nas` path for Jellyfin. These are network mounts, not copied
media; ensure the Synology and network are up when a dependent service starts.

1. Create `/home/jonas/services/secrets/nas.creds` as root using `sudoedit`.
   It must contain `username=<account>` and `password=<password>` on separate
   lines; add `domain=<domain>` only if needed. Set its owner to `root:root`
   and permissions to `0600`. Use an account with read access to `workouts`
   and write access to `shared_common/backup_bitwarden`. Credentials are not
   in Nix or Git. Rotate the source CIFS password exposed by Docker metadata.
2. With the NAS running, test the mounts and the legacy path:

   ```sh
   sudo systemctl start "$(systemd-escape --path --suffix=mount /home/jonas/services/nas/workouts)"
   sudo systemctl start "$(systemd-escape --path --suffix=mount /home/jonas/services/nas/shared-common)"
   sudo systemctl start mnt-nas.mount
   findmnt /mnt/nas
   findmnt /home/jonas/services/nas/shared-common
   ls -ld /home/jonas/services/nas/shared-common/backup_bitwarden
   ```

   Confirm the actual directory exists and the Synology permissions allow
   writing before running the backup. Mount options and the NAS address can be
   changed in `nas.nix`; other host-only services can use these shared paths.
3. Jellyfin requires `/mnt/nas` before starting. The Bitwarden job requires
   `shared-common` and checks both its mount and backup directory before
   launching. If the NAS is off, these operations fail rather than starting
   against empty local directories. Mounts are not started at boot unless a
   dependent service requests them; once migration markers are enabled,
   Jellyfin will request its share on boot. If the NAS disappears after a
   mount, CIFS I/O may fail or block while the kernel retries; monitor it.

## Manual fallback: Copying Docker data

Only perform these steps after an independent backup and stopping the relevant
writers on the old machine. A live filesystem copy of PostgreSQL, MariaDB,
Redis or SQLite is not a consistent backup. For Norish, stop the app first,
then its database and Redis; stop the proxy and Gitea before copying them.
Firefly and Guacamole were stopped during investigation, but check again.
Application-consistent database dumps are an alternative; follow the upstream
restore procedure for the matching image.

On the **new** host, this pattern streams a stopped container's directory
without an intermediate archive. It preserves numeric ownership, so extract
as root. `docker cp` reads the named container's mounted data even when stopped:

```sh
sudo install -d /home/jonas/services/norish/postgres
ssh ubuntu@ubuntu2004 'docker cp norish-db-1:/var/lib/postgresql/data -' \
  | sudo tar -xpf - --numeric-owner --strip-components=1 -C /home/jonas/services/norish/postgres
```

Use the same pattern, first creating each destination, for these paths:

| Source container and path | Destination directory |
| --- | --- |
| `norish-norish-1:/app/uploads` | `/home/jonas/services/norish/uploads` |
| `norish-redis-1:/data` | `/home/jonas/services/norish/redis` |
| `nginx-proxy-manager-app-1:/data` | `/home/jonas/services/proxy/data` |
| `nginx-proxy-manager-app-1:/etc/letsencrypt` | `/home/jonas/services/proxy/letsencrypt` |
| `Guacamole:/config` | `/home/jonas/services/guacamole/config` |
| `Firefly-DB:/var/lib/mysql` | `/home/jonas/services/firefly/mysql` |
| `Firefly-REDIS:/data` | `/home/jonas/services/firefly/redis` |
| `Firefly:/var/www/html/storage/upload` | `/home/jonas/services/firefly/upload` |

Guacamole includes PostgreSQL in `/config`; preserve the entire directory and
numeric ownership. The old container used PUID 1026; configure the new
`guacamole.env` from the actual Jonas UID and `users` GID, and remap only
files owned by the old PUID. Do not recursively change PostgreSQL ownership.
The source embeds PostgreSQL 9.6 and uses the JDBC authentication extension;
the native NixOS Guacamole modules do not package that extension. The pinned
container is a compatibility-first restore, not a fully native migration.
Plan a separately tested database and authentication migration, and upgrade
the obsolete image/database after confirming a restorable backup.

After files, secrets and backups are verified, activate each project
individually. For example, Norish:

```sh
sudo touch /home/jonas/services/norish/.ready
sudo systemctl start werkstatt-norish
sudo systemctl status werkstatt-norish
sudo docker compose -p werkstatt-norish -f /etc/werkstatt/compose/norish.json ps
sudo docker compose -p werkstatt-norish -f /etc/werkstatt/compose/norish.json logs --tail=100
```

Repeat with `proxy`, `guacamole` and `firefly`, creating the matching marker
and starting `werkstatt-<name>`. Check logs before opening the service to
users. A marker is not a backup or health check. `systemctl stop` takes down
the corresponding Compose project but leaves bind-mounted data intact.
Images are pinned to source digests for the initial restore; check image
availability and plan security upgrades once migration is complete.

For the proxy, inspect every restored route, hostname, certificate and
upstream. The old disabled ownCloud route references an unselected service.
Old upstream IPs or Docker network names may refer to Ubuntu and need changing.
Test certificate renewal and router forwarding only after cutover. Do not
expose the admin UI to the public internet unintentionally.

## Manual fallback: Native Gitea migration

This is the **Docker** Gitea, not the old native instance. The version jump
from 1.21.3 to 1.27.3 upgrades SQLite and is not reversible by downgrading the
binary. Read the upstream upgrade notes and breaking changes, test on a copy,
and retain an untouched 1.21.3 backup. If direct upgrade is rejected, use the
intermediate releases required by Gitea on the copied data before attempting
the native service; never experiment on the only backup.

1. Stop the old Docker Gitea during the cutover window. From the new host:

   ```sh
   sudo install -d -m 0700 /home/jonas/services/migration/gitea-source
   ssh ubuntu@ubuntu2004 'docker cp gitea:/data -' \
     | sudo tar -xpf - --numeric-owner --strip-components=1 -C /home/jonas/services/migration/gitea-source
   ```

2. The archive has `gitea/gitea.db`, attachments, avatars, packages, indexes
   and other app data; repositories are `git/repositories` and LFS is
   `git/lfs`. Copy `gitea/` into `/home/jonas/services/gitea/data/`,
   `git/repositories/` into `/home/jonas/services/gitea/repositories/`, and
   `git/lfs/` into `/home/jonas/services/gitea/data/lfs/`. Preserve an
   untouched archive. Ensure the resulting files are owned by `jonas:users`.
3. The old `gitea/conf/app.ini` contains secrets. Before starting the new
   service, securely place its `security.SECRET_KEY`, `security.INTERNAL_TOKEN`,
   `oauth2.JWT_SECRET` and `server.LFS_JWT_SECRET` values respectively in
   `custom/conf/secret_key`, `custom/conf/internal_token`,
   `custom/conf/oauth2_jwt_secret` and `custom/conf/lfs_jwt_secret` under
   `/home/jonas/services/gitea`. Files should be owned by Jonas and mode 0600.
   Keep the original config privately for reference, not in Git. NixOS
   regenerates `custom/conf/app.ini` and generates new secrets if those files
   are missing, potentially invalidating existing state. The original source
   has an empty `SECRET_KEY`: use Gitea 1.21.3's documented legacy fallback,
   not a newly generated key. The migration script handles this automatically.
4. Compare remaining old settings and custom templates with Nix settings.
   Check `ROOT_URL`, the public SSH hostname and SSH port 2221. Old Git remotes
   may need updating. Source registration and OpenID remain enabled; disable
   them in Nix if they are not intended for public access.
5. Create `/home/jonas/services/gitea/.ready`, start `gitea.service`, and
   inspect `journalctl -u gitea -b`. Test login, repositories, Git over HTTP
   and SSH, LFS, attachments, packages, webhooks and redirects before cutover.

## Manual fallback: Native Jellyfin migration

1. Stop the old `jellyfin.service` during the cutover window. On Ubuntu copy
   `/var/lib/jellyfin/` to `/home/jonas/services/jellyfin/data/` on the new
   host and `/etc/jellyfin/` to `/home/jonas/services/jellyfin/config/`.
   Source directories may require sudo. For example, from an interactive
   shell on the **source**:

   ```sh
   sudo tar -C /var/lib/jellyfin -cpf - . | ssh jonas@werkstatt 'mkdir -p ~/services/jellyfin/data && tar -C ~/services/jellyfin/data -xpf -'
   sudo tar -C /etc/jellyfin -cpf - . | ssh jonas@werkstatt 'mkdir -p ~/services/jellyfin/config && tar -C ~/services/jellyfin/config -xpf -'
   ```

   Substitute the new host's temporary DNS name or IP if `werkstatt` still
   points at the old machine. Verify ownership and permissions on the target.
   Cache and logs can be recreated; retain them separately if needed.
2. The Synology setup above preserves the `/mnt/nas` library path. Jellyfin
   requires that mount and will fail to start when it cannot be mounted. Other
   library paths must also exist or be changed in Jellyfin. Hardware
   transcoding and GPU permissions depend on the new hardware and are not
   assumed here. The restore script rewrites the source's legacy
   `/var/lib/jellyfin/transcodes` path to the home-based Jellyfin cache; custom
   transcode paths are left unchanged and should be checked separately.
3. After checking backup and permissions, create
   `/home/jonas/services/jellyfin/.ready` and start `jellyfin.service`. Check
   logs, users, watch history, plugins, media access and actual playback. The
   target may upgrade the database; keep the pre-upgrade backup.

## Bitwarden backup

This remains a manually triggered one-shot job, as on the source; it is not
silently scheduled. Set up the Synology mounts above and the root-only env
file. Verify the NAS output destination, backup password and Bitwarden
credentials before running it:

```sh
sudo touch /home/jonas/services/bitwarden-backup/.ready
sudo systemctl start werkstatt-bitwarden-backup
sudo journalctl -u werkstatt-bitwarden-backup -n 100
```

The output is the mounted Synology directory
`//10.0.2.200/shared_common/backup_bitwarden`. The unit starts the share mount
on demand and refuses to run if it is not mounted or the directory is absent.
If the NAS is off, start the job again after it is available. Test restoration
of an encrypted backup and rotate the exposed CIFS credential.

## Home Assistant OS VM

The VM service automatically downloads the latest stable official Home
Assistant OS KVM QCOW2 image when its disk is absent, verifies the published
SHA-256 checksum, and starts it once `br0` is available. The first boot may
take several minutes; open `http://homeassistant.local:8123` or the guest's LAN
IP to use the onboarding assistant. No installer ISO is needed. The image is
downloaded only for initial provisioning; Home Assistant manages its own OS
updates, independently of Nix rebuilds. Existing disks are never replaced.

Libvirt assigns the MAC automatically; inspect it with
`sudo virsh -c qemu:///system domiflist home-assistant --inactive` for a DHCP
reservation. The service preserves the UUID and MAC when redefining the VM.
Network access and GitHub availability are required for initial provisioning;
if it fails, inspect `journalctl -u werkstatt-home-assistant -b` and restart
the service after fixing the problem.

If migrating your old VM rather than starting fresh, you still perform that
migration yourself. Check RAM, CPUs, firmware mode, disk bus and any
Zigbee/Z-Wave/USB or other passthrough before the first boot. The default guest
is non-secure-boot UEFI, q35, virtio disk and virtio NIC. If the original used
a different setup, change the definition or use a tested backup/restore rather
than assuming it will boot. Libvirt metadata is managed by the host; disk and
UEFI variables are under Jonas's home.

1. Shut down the old guest cleanly and back it up, including firmware variables.
   Never attach the same writable disk to two running VMs.
2. Before enabling the bridge and starting the VM service, import or convert a
   **copy** of the disk to qcow2 at
   `/home/jonas/services/home-assistant/home-assistant.qcow2`. For example,
   on the new host, `qemu-img info <source-disk>` followed by
   `qemu-img convert -p -O qcow2 <source-disk> <destination>`; make sure the
   source format and all snapshot/backing files are understood first. Do not
   overwrite the only backup. If carrying forward UEFI variables, confirm they
   are compatible with QEMU/OVMF; VMware firmware state is not generally
   interchangeable. If a fresh VM was already provisioned, stop the systemd
   service, shut down the guest with `sudo virsh -c qemu:///system shutdown
   home-assistant`, and verify it is stopped with `virsh domstate` before
   moving the fresh disk aside and importing the old copy. Do not overwrite
   either disk or run a rebuild that restarts the service during the import.
3. Configure `10.0.2.136` inside Home Assistant OS, or reserve it on your LAN
   DHCP server for the libvirt-assigned MAC. Nix and the bridge do not assign
   the guest's IP. Use the actual LAN subnet, gateway and DNS; do not create a
   second DHCP server on the LAN. Confirm the old VM is offline.
4. Verify `br0` and its physical port, then run
   `sudo systemctl start werkstatt-home-assistant`. Check
   `sudo virsh -c qemu:///system domstate home-assistant` and use virt-manager
   or the local VNC console to inspect boot. Ensure `10.0.2.136:8123`, local
   discovery, integrations, USB devices and the guest's Tailscale all work.
5. Reboot the host and verify the bridge and VM return. Review guest shutdown
   behavior and keep a tested Home Assistant backup independent of the disk.
   Nix changes persistent VM settings; a running guest may need a clean restart
   for those changes to take effect.

## Cutover, operations and rollback

1. With old writers still stopped, take a final consistent copy and repeat
   restore checks. Point DNS, reverse-proxy upstreams and router forwards at
   the new machine only after testing. Do not let both copies accept writes or
   two Home Assistant VMs control the same devices.
2. Check `systemctl --failed`, service journals, Netdata, `docker compose ...
   ps`, HTTPS certificates and tailnet ACLs. Verify application logins,
   database contents, backups, media and remote access.
3. Keep the old services stopped but recoverable until you have a verified
   backup of the new system and a rollback window. Reversing DNS alone does
   not synchronize writes made on the new host. To roll back, stop the new
   writers first and decide how to preserve or reconcile those writes; never
   feed upgraded Gitea or Jellyfin databases to older binaries.
4. Back up `/home/jonas/services` regularly, including app data, secrets, VM
   disk and firmware state. Quiesce databases and the VM or use consistent
   snapshots/dumps. Nix does not back up application data. Docker's configured
   data root and classic image store live under home; normal NixOS, libvirt
   and container runtime metadata and transient state can still exist in
   standard system paths. Verify with `docker info` after installation.

## Exposure and permissions

Compose services retain their original host port bindings, including
`0.0.0.0`. Docker can bypass the usual NixOS firewall for published ports.
Native Gitea ports 5000/2221, Jellyfin 8096 and SSH 22 are opened in the
firewall. Use router rules, VLANs and application authentication to restrict
LAN/public access; Tailscale Serve does not make original LAN ports private.
Netdata binds to loopback but is available to authorized tailnet users via
Serve. The proxy admin UI also needs strict access control.

Membership in Docker and libvirt groups is effectively privileged. Netdata runs
as Jonas and can access Docker and other data available to that account.
Protect the desktop session, tailnet access and backups accordingly. The
shared desktop configuration includes an opt-in WireGuard kill switch;
enabling it can interrupt server, bridge and tailnet connectivity.