#!/usr/bin/env python3
"""Back up the selected Ubuntu services and restore them on werkstatt."""

import configparser
import argparse
import contextlib
import fcntl
import getpass
import hashlib
import json
import os
import grp
import pwd
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from pathlib import Path
from urllib.parse import unquote, urlsplit


GITEA_LEGACY_SECRET = "!#@FDEWREWR&*("
NAS_SHARE = "//10.0.2.200/shared_common"
NAS_FOLDER = "services_migration"
DESTINATION = Path("/home/jonas/services")
COMPOSE_DIRECTORY = Path("/etc/werkstatt/compose")
REQUIRED_VOLUMES = {
    "gitea_gitea", "norish_norish_data", "norish_db_data", "norish_redis_data",
    "guacamole_guacamole_config", "firefly-iii_db", "firefly-iii_redis",
    "firefly-iii_upload", "portainer_data",
}
REQUIRED_CONTAINERS = {
    "gitea", "norish-norish-1", "norish-db-1", "norish-redis-1", "norish-obscura-1",
    "nginx-proxy-manager-app-1", "Guacamole", "Firefly", "Firefly-DB",
    "Firefly-REDIS", "Firefly-Cron", "bitwarden_backup",
}
EXPECTED_DIGESTS = {
    "gitea": "a5bb316b224a9887756f5762488a6efe4065cf9cdbdf2c6d059f6cb1b6a0ce8a",
    "norish-norish-1": "f96ba007c7bdd7b6640f34c2ffbe63a647a2f9e2a291afdf666f895e7f6f168b",
    "norish-db-1": "b0f9560a2de083e2cc7382e75f808c7381a32852a7ec49117deedb300e552b24",
    "norish-redis-1": "8a1efc5f479551822b47424ccae982026b633f28818eab0387348120a61e10e2",
    "norish-obscura-1": "d3b30af8d88a73685422d9c29a7689c0952966e8d6e87eb00edcf6c2c85defe6",
    "nginx-proxy-manager-app-1": "081c4c544ad5da81022b3b030c2ba50175923bc87a534bce8b52f870e695e9f1",
    "Guacamole": "6128500fa30f0c3cc3c9079bc977b7e2d2159d58d0fa16f084cb1d115ea6ce49",
    "Firefly": "4d71e7207ac46661bed6fcd13e824c739dfdb331a5d58dc7e048fc60c5382da7",
    "Firefly-DB": "9da6213d1a5714c4585c9c0003c51510b320d6f60e53d78701fe1e194126249f",
    "Firefly-REDIS": "a7cee7c8178ff9b5297cb109e6240f5072cdaaafd775ce6b586c3c704b06458e",
    "Firefly-Cron": "51b67269f354137895d43f3b3d810bfacd3945438e94dc5ac55fdac340352f48",
    "bitwarden_backup": "3bc5253b3396af990318d5603bc45e3b7c40b418410eec4735f1b75a6abb1618",
}
APPLICATION_UNITS = (
    "cron.service", "jupyterlab.service", "supervisor.service", "gitea.service",
    "jellyfin.service", "mariadb.service", "noip2.service", "openvpn-server@server.service",
)
SOURCE_FOLDERS = {
    "jellyfin-data": "/var/lib/jellyfin", "jellyfin-config": "/etc/jellyfin",
    "proxy-data": "/data/compose/2/data", "proxy-certificates": "/data/compose/2/letsencrypt",
    "home": "/home", "compose-data": "/data/compose", "system-etc": "/etc",
    "native-gitea": "/var/lib/gitea", "native-mysql": "/var/lib/mysql", "usr-local": "/usr/local",
    "root-home": "/root", "cron-spool": "/var/spool/cron", "web-root": "/var/www",
    "system-backups": "/var/backups", "opt": "/opt", "srv": "/srv",
}
REQUIRED_FOLDERS = {"jellyfin-data", "jellyfin-config", "proxy-data", "proxy-certificates"}
RESTORE_ARCHIVES = {
    "gitea-source": "volumes/gitea_gitea.tar",
    "norish-uploads": "volumes/norish_norish_data.tar",
    "norish-postgres": "volumes/norish_db_data.tar",
    "norish-redis": "volumes/norish_redis_data.tar",
    "guacamole": "volumes/guacamole_guacamole_config.tar",
    "firefly-mysql": "volumes/firefly-iii_db.tar",
    "firefly-redis": "volumes/firefly-iii_redis.tar",
    "firefly-upload": "volumes/firefly-iii_upload.tar",
    "proxy-data": "system/proxy-data.tar",
    "proxy-certificates": "system/proxy-certificates.tar",
    "jellyfin-data": "system/jellyfin-data.tar",
    "jellyfin-config": "system/jellyfin-config.tar",
}
SERVICE_PROJECTS = (
    "gitea", "jellyfin", "proxy", "norish", "guacamole", "firefly",
    "bitwarden-backup",
)
START_UNITS = (
    "gitea", "jellyfin", "werkstatt-proxy", "werkstatt-norish",
    "werkstatt-guacamole", "werkstatt-firefly",
)
SERVICE_REQUIRED_DIRS = (
    "gitea/repositories", "gitea/data", "jellyfin/data", "jellyfin/config",
    "proxy/data", "proxy/letsencrypt", "norish/uploads", "norish/postgres",
    "norish/redis", "guacamole/config", "firefly/mysql", "firefly/redis",
    "firefly/upload", "bitwarden-backup", "secrets",
)
SERVICE_REQUIRED_FILES = (
    "gitea/data/gitea.db", "gitea/custom/conf/secret_key",
    "gitea/custom/conf/internal_token",
    "gitea/custom/conf/oauth2_jwt_secret", "gitea/custom/conf/lfs_jwt_secret",
    "secrets/nas.creds", "secrets/guacamole.env", "secrets/norish.env",
    "secrets/norish-db.env", "secrets/norish-obscura.env",
    "secrets/firefly.env", "secrets/firefly-db.env",
    "secrets/firefly-cron.env", "secrets/bitwarden-backup.env",
)


class MigrationError(Exception):
    pass


def compose_env_line(name, value):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise MigrationError(f"Invalid environment variable name: {name!r}")
    if "\n" in value or "\r" in value or "\x00" in value:
        raise MigrationError(f"Multiline or NUL value is unsupported for {name}")
    return f"{name}={value}\n"


def parse_gitea_config(text):
    parser = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        parser.read_string("[global]\n" + text)
    except configparser.Error as error:
        raise MigrationError("Cannot parse the source Gitea configuration safely") from error
    for section, key in (("security", "SECRET_KEY_URI"), ("security", "INTERNAL_TOKEN_URI"),
                         ("oauth2", "JWT_SECRET_URI"), ("server", "LFS_JWT_SECRET_URI")):
        if parser.get(section, key, fallback="").strip():
            raise MigrationError(f"Gitea {section}.{key} needs manual migration")
    names = {
        "secret_key": ("security", "SECRET_KEY"),
        "internal_token": ("security", "INTERNAL_TOKEN"),
        "oauth2_jwt_secret": ("oauth2", "JWT_SECRET"),
        "lfs_jwt_secret": ("server", "LFS_JWT_SECRET"),
    }
    secrets = {name: parser.get(section, key, fallback="").strip() for name, (section, key) in names.items()}
    if any(len(value) >= 2 and value[0] in "'\"`" and value[-1] == value[0] for value in secrets.values()):
        raise MigrationError("Quoted Gitea secrets need manual migration")
    if not secrets["secret_key"]:
        secrets["secret_key"] = GITEA_LEGACY_SECRET
    missing = [name for name, value in secrets.items() if not value]
    if missing:
        raise MigrationError(f"Missing Gitea secrets: {', '.join(missing)}")
    return secrets


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(archive, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    with tarfile.open(archive, "r:") as source:
        for member in source:
            tarfile.data_filter(member, str(destination))
    command("tar", "--extract", "--file", str(archive), "--directory", str(destination),
            "--numeric-owner", "--same-owner", "--same-permissions", "--acls", "--xattrs", "--xattrs-include=*")


def command(*arguments, capture=False, check=True):
    return subprocess.run(arguments, check=check, text=True, capture_output=capture)


def docker_json(*arguments):
    return json.loads(command("docker", *arguments, capture=True).stdout)


def require_commands(names):
    missing = [name for name in names if shutil.which(name) is None]
    if missing:
        raise MigrationError(f"Missing required commands: {', '.join(missing)}")


def require_confirmation(prompt, expected):
    print(prompt, flush=True)
    if input(f"Type {expected} to continue: ").strip() != expected:
        raise MigrationError("Confirmation not given; no further changes made")


def ask_credentials():
    username = input("Synology username: ").strip()
    password = getpass.getpass("Synology password: ")
    domain = input("Synology domain (leave blank if not needed): ").strip()
    if not username or not password or any(any(char in value for char in "\n\r\x00") for value in (username, password, domain)):
        raise MigrationError("Synology credentials must be nonempty and single-line")
    return {"username": username, "password": password, "domain": domain}


def credentials_text(credentials):
    lines = [f"username={credentials['username']}", f"password={credentials['password']}"]
    if credentials["domain"]:
        lines.append(f"domain={credentials['domain']}")
    return "\n".join(lines) + "\n"


@contextlib.contextmanager
def mounted_nas(credentials, read_only):
    root = Path(tempfile.mkdtemp(prefix="werkstatt-migration-", dir="/run"))
    credentials_file = root / "nas.creds"
    mountpoint = root / "share"
    try:
        write_private(credentials_file, credentials_text(credentials))
        mountpoint.mkdir()
        options = f"credentials={credentials_file},vers=3.0,nosuid,nodev,noexec,uid=0,gid=0,file_mode=0600,dir_mode=0700"
        if read_only:
            options += ",ro"
        command("mount", "-t", "cifs", NAS_SHARE, str(mountpoint), "-o", options)
        credentials_file.unlink()
        if not os.path.ismount(mountpoint):
            raise MigrationError("The Synology share did not mount; refusing local fallback")
        actual = command("findmnt", "-n", "-o", "SOURCE,FSTYPE", "-T", str(mountpoint), capture=True).stdout.split()
        if len(actual) != 2 or actual[0].lower() != NAS_SHARE.lower() or actual[1] != "cifs":
            raise MigrationError("Mounted filesystem is not the expected Synology CIFS share")
        yield mountpoint
    finally:
        credentials_file.unlink(missing_ok=True)
        unmounted = True
        if os.path.ismount(mountpoint):
            result = command("umount", str(mountpoint), check=False)
            if result.returncode:
                print(f"WARNING: could not unmount {mountpoint}; leaving it untouched", file=sys.stderr)
                unmounted = False
        if unmounted:
            if mountpoint.exists():
                mountpoint.rmdir()
            root.rmdir()


@contextlib.contextmanager
def exclusive_lock():
    with open("/run/werkstatt-migration.lock", "a", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise MigrationError("Another migration is already running") from error
        yield


def write_private(path, contents):
    path = Path(path)
    with open(path, "x", encoding="utf-8") as output:
        os.fchmod(output.fileno(), 0o600)
        output.write(contents)
        output.flush()
        os.fsync(output.fileno())


def archive_directory(source, destination):
    source = Path(source)
    destination = Path(destination)
    if not source.is_dir() or source.is_symlink():
        raise MigrationError(f"Source directory is missing or is a symlink: {source}")
    with open(destination, "xb") as output:
        process = subprocess.run(
            ["tar", "--one-file-system", "--numeric-owner", "--acls", "--xattrs",
             "--sparse", "-C", str(source), "-cf", "-", "."], stdout=output,
        )
        if process.returncode:
            raise MigrationError(f"Failed to archive {source}; the snapshot is incomplete")
        output.flush()
        os.fsync(output.fileno())
    verify_tar(destination)
    return sha256_file(destination)


def archive_command(arguments, destination):
    with open(destination, "xb") as output:
        process = subprocess.run(arguments, stdout=output)
        if process.returncode:
            raise MigrationError(f"Archive command failed: {arguments[0]}; snapshot is incomplete")
        output.flush()
        os.fsync(output.fileno())
    verify_tar(destination)
    return sha256_file(destination)


def verify_tar(path):
    try:
        with tarfile.open(path, "r:") as archive:
            for member in archive:
                if member.isfile():
                    stream = archive.extractfile(member)
                    if stream is None:
                        raise MigrationError(f"Cannot read archive member in {path}")
                    while stream.read(1024 * 1024):
                        pass
    except (tarfile.TarError, OSError) as error:
        raise MigrationError(f"Invalid or unreadable archive: {path}") from error


def validate_source_images(containers, images):
    by_image = {image["Id"]: image for image in images}
    by_name = {item["Name"].lstrip("/"): item for item in containers}
    for name, digest in EXPECTED_DIGESTS.items():
        if name not in by_name or by_name[name]["Image"] not in by_image:
            raise MigrationError(f"Cannot identify source image for {name}")
        image = by_image[by_name[name]["Image"]]
        digests = {entry.rsplit("@sha256:", 1)[-1] for entry in image.get("RepoDigests") or []}
        if digest not in digests:
            raise MigrationError(f"Source image changed or has no expected digest: {name}; review migration compatibility before stopping services")


def inspect_source():
    container_ids = command("docker", "ps", "-aq", "--no-trunc", capture=True).stdout.split()
    if not container_ids:
        raise MigrationError("No Docker containers found on the Ubuntu source")
    containers = docker_json("inspect", "--size", *container_ids)
    names = {item["Name"].lstrip("/") for item in containers}
    missing = REQUIRED_CONTAINERS - names
    if missing:
        raise MigrationError(f"Required source containers not found: {', '.join(sorted(missing))}")
    volume_names = command("docker", "volume", "ls", "-q", capture=True).stdout.split()
    volumes = docker_json("volume", "inspect", *volume_names) if volume_names else []
    local = {}
    external = []
    for volume in volumes:
        name = volume["Name"]
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
            raise MigrationError(f"Unexpected Docker volume name: {name!r}")
        if volume["Driver"] != "local" or volume.get("Options"):
            external.append(name)
        else:
            path = Path(volume["Mountpoint"])
            if not path.is_dir() or path.is_symlink() or os.path.ismount(path):
                raise MigrationError(f"Unexpected local Docker volume location: {name}")
            local[name] = str(path)
    missing = REQUIRED_VOLUMES - local.keys()
    if missing:
        raise MigrationError(f"Required local volumes missing or external: {', '.join(sorted(missing))}")
    image_ids = sorted({item["Image"] for item in containers})
    images = docker_json("image", "inspect", *image_ids)
    validate_source_images(containers, images)
    units = {}
    for unit in APPLICATION_UNITS:
        result = command("systemctl", "show", unit, "--property=LoadState,ActiveState", "--value", capture=True, check=False)
        if result.returncode == 0:
            units[unit] = result.stdout.splitlines()
    return {"containers": containers, "volumes": volumes, "local_volumes": local,
            "external_volumes": external, "images": images, "units": units}


def stop_source(metadata):
    for unit in APPLICATION_UNITS:
        loaded = command("systemctl", "show", unit, "--property=LoadState", "--value", capture=True, check=False)
        if loaded.returncode == 0 and loaded.stdout.strip() == "loaded":
            command("systemctl", "stop", unit)
    running = command("docker", "ps", "-q", "--no-trunc", capture=True).stdout.split()
    if running:
        command("docker", "stop", "--time", "120", *running)
    assert_source_quiet(metadata)


def assert_source_quiet(metadata=None):
    running = command("docker", "ps", "-q", capture=True).stdout.split()
    if running:
        raise MigrationError("Docker containers restarted during migration; snapshot is incomplete")
    if metadata is not None:
        container_ids = set(command("docker", "ps", "-aq", "--no-trunc", capture=True).stdout.split())
        if container_ids != {item["Id"] for item in metadata["containers"]}:
            raise MigrationError("Docker container inventory changed during migration")
        volume_names = set(command("docker", "volume", "ls", "-q", capture=True).stdout.split())
        if volume_names != {item["Name"] for item in metadata["volumes"]}:
            raise MigrationError("Docker volume inventory changed during migration")
    for unit in APPLICATION_UNITS:
        state = command("systemctl", "show", unit, "--property=ActiveState", "--value", capture=True, check=False)
        if state.returncode == 0 and state.stdout.strip() not in {"inactive", "failed", ""}:
            raise MigrationError(f"Source unit is still active: {unit}")


def estimate_snapshot_size(metadata):
    paths = list(metadata["local_volumes"].values())
    for name, source in SOURCE_FOLDERS.items():
        if Path(source).is_dir():
            paths.append(source)
        elif name in REQUIRED_FOLDERS:
            raise MigrationError(f"Required source directory missing: {source}")
    total = 0
    for path in paths:
        result = command("du", "--apparent-size", "--bytes", "--summarize", "--one-file-system", path, capture=True)
        total += int(result.stdout.split()[0])
    total += sum(int(item.get("SizeRootFs") or 0) for item in metadata["containers"])
    total += sum(int(item.get("Size") or 0) for item in metadata["images"])
    return total + total // 10 + 1024**3


def require_nas_mount(share):
    if not os.path.ismount(share):
        raise MigrationError("Synology mount disappeared; refusing to write to a local fallback")


def create_snapshot(share):
    require_confirmation(
        "This stops ALL running Docker containers and the listed application units. "
        "SSH, networking, Docker itself and Tailscale remain running. "
        "Close desktop applications first; use a console or tmux. "
        "The NAS snapshot contains PLAINTEXT credentials and private data.", "STOP SERVICES"
    )
    metadata = inspect_source()
    require_nas_mount(share)
    root = Path(share) / NAS_FOLDER
    root.mkdir(mode=0o700, exist_ok=True)
    if root.is_symlink() or not root.is_dir():
        raise MigrationError("Migration destination is not a real NAS directory")
    required_bytes = estimate_snapshot_size(metadata)
    available_bytes = shutil.disk_usage(root).free
    if available_bytes < required_bytes:
        raise MigrationError(f"NAS space is insufficient: need approximately {required_bytes} bytes, have {available_bytes}")
    name = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + "-" + uuid.uuid4().hex[:8]
    snapshot = root / name
    snapshot.mkdir(mode=0o700)
    (snapshot / "volumes").mkdir(mode=0o700)
    (snapshot / "system").mkdir(mode=0o700)
    (snapshot / "containers").mkdir(mode=0o700)
    print(f"Snapshot: {NAS_SHARE}/{NAS_FOLDER}/{snapshot.name}", flush=True)
    stop_source(metadata)
    write_private(snapshot / "source-state.json", json.dumps(metadata, indent=2))
    checksums = {"source-state.json": sha256_file(snapshot / "source-state.json")}
    for name, source in sorted(metadata["local_volumes"].items()):
        require_nas_mount(share)
        relative = f"volumes/{name}.tar"
        print(f"Archiving volume {name}", flush=True)
        checksums[relative] = archive_directory(source, snapshot / relative)
    for name, source in SOURCE_FOLDERS.items():
        require_nas_mount(share)
        if not Path(source).is_dir():
            if name in REQUIRED_FOLDERS:
                raise MigrationError(f"Required source directory missing: {source}")
            continue
        relative = f"system/{name}.tar"
        print(f"Archiving {source}", flush=True)
        checksums[relative] = archive_directory(source, snapshot / relative)
    for item in metadata["containers"]:
        require_nas_mount(share)
        name = item["Name"].lstrip("/")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name):
            raise MigrationError(f"Unexpected Docker container name: {name!r}")
        relative = f"containers/{name}.tar"
        print(f"Archiving container filesystem {name}", flush=True)
        checksums[relative] = archive_command(["docker", "export", item["Id"]], snapshot / relative)
    images = []
    for image in metadata["images"]:
        images.extend(image.get("RepoTags") or [image["Id"]])
    print("Archiving Docker images", flush=True)
    require_nas_mount(share)
    checksums["docker-images.tar"] = archive_command(["docker", "image", "save", *sorted(set(images))], snapshot / "docker-images.tar")
    assert_source_quiet(metadata)
    for relative, expected in checksums.items():
        require_nas_mount(share)
        if sha256_file(snapshot / relative) != expected:
            raise MigrationError(f"NAS readback checksum mismatch: {relative}")
    manifest = {"format": 1, "source": socket.gethostname().split(".", 1)[0], "created": name,
                "external_volumes_not_copied": metadata["external_volumes"], "files": checksums}
    write_private(snapshot / "manifest.json", json.dumps(manifest, indent=2))
    write_private(snapshot / "COMPLETE", sha256_file(snapshot / "manifest.json") + "\n")
    print("Snapshot verified. Services remain stopped; keep this backup and make an independent copy.", flush=True)
    print("External Docker volumes were not copied:", ", ".join(metadata["external_volumes"]) or "none")
    print("The separate Home Assistant VM and host disks are NOT included.")
    return snapshot


def load_manifest(snapshot):
    snapshot = Path(snapshot)
    if snapshot.is_symlink() or not snapshot.is_dir():
        raise MigrationError("Snapshot is not a real directory")
    complete = snapshot / "COMPLETE"
    manifest_path = snapshot / "manifest.json"
    if complete.is_symlink() or manifest_path.is_symlink() or not complete.is_file() or not manifest_path.is_file():
        raise MigrationError("Snapshot has no safe completion marker or manifest")
    recorded = complete.read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"[0-9a-f]{64}", recorded) or sha256_file(manifest_path) != recorded:
        raise MigrationError("Snapshot manifest checksum does not match")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("format") != 1 or not isinstance(manifest.get("files"), dict):
        raise MigrationError("Unsupported or invalid snapshot manifest")
    for relative, digest in manifest["files"].items():
        path = Path(relative)
        if path.is_absolute() or not path.parts or any(part in {".", ".."} for part in path.parts):
            raise MigrationError(f"Unsafe snapshot path: {relative!r}")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise MigrationError(f"Invalid snapshot checksum for {relative!r}")
        current = snapshot
        for component in path.parts:
            current = current / component
            if current.is_symlink():
                raise MigrationError(f"Snapshot contains a symlink: {relative!r}")
        if not current.is_file():
            raise MigrationError(f"Snapshot file is missing: {relative!r}")
    required = {"source-state.json", "docker-images.tar"}
    required.update(f"volumes/{name}.tar" for name in REQUIRED_VOLUMES)
    required.update(f"system/{name}.tar" for name in REQUIRED_FOLDERS)
    missing = required - manifest["files"].keys()
    if missing:
        raise MigrationError(f"Snapshot is missing required files: {', '.join(sorted(missing))}")
    return manifest


def verify_snapshot(snapshot, manifest, check_mount=None):
    for relative, expected in sorted(manifest["files"].items()):
        if check_mount is not None:
            require_nas_mount(check_mount)
        print(f"Verifying {relative}", flush=True)
        if sha256_file(Path(snapshot) / relative) != expected:
            raise MigrationError(f"Snapshot checksum mismatch: {relative}")


def select_snapshot(share, requested=None):
    root = Path(share) / NAS_FOLDER
    if root.is_symlink() or not root.is_dir():
        raise MigrationError("NAS migration directory not found")
    choices = sorted(path for path in root.iterdir() if path.is_dir() and not path.is_symlink() and (path / "COMPLETE").is_file())
    if not choices:
        raise MigrationError("No complete snapshot found on the NAS")
    if requested is not None:
        matching = [path for path in choices if path.name == requested]
        if len(matching) != 1:
            raise MigrationError("Requested snapshot is not a complete snapshot on the NAS")
        snapshot = matching[0]
    else:
        snapshot = choices[-1]
    print(f"Selected complete snapshot: {snapshot.name}")
    others = [path.name for path in choices if path != snapshot]
    if others:
        print("Other complete snapshots:", ", ".join(others))
    require_confirmation("Confirm this is the intended and latest source snapshot.", "RESTORE")
    return snapshot


def container_environment(metadata, name):
    matches = [item for item in metadata["containers"] if item["Name"].lstrip("/") == name]
    if len(matches) != 1:
        raise MigrationError(f"Expected exactly one source container named {name}")
    result = {}
    for entry in matches[0]["Config"].get("Env") or []:
        if "=" in entry:
            key, value = entry.split("=", 1)
            result[key] = value
    return result


def selected_environment(environment, keys, required):
    missing = [key for key in required if key not in environment or not environment[key]]
    if missing:
        raise MigrationError(f"Required source environment values missing: {', '.join(missing)}")
    return "".join(compose_env_line(key, environment[key]) for key in keys if key in environment)


def walk_paths(root):
    root = Path(root)
    yield root
    for current, directories, files in os.walk(root, followlinks=False):
        for name in directories + files:
            yield Path(current) / name


def change_owner(root, uid, gid, old_uid=None):
    for path in walk_paths(root):
        current = path.lstat()
        if old_uid is None or current.st_uid == old_uid:
            os.chown(path, uid, gid, follow_symlinks=False)


def move_directory(source, destination):
    source = Path(source)
    destination = Path(destination)
    if not source.is_dir() or source.is_symlink():
        raise MigrationError(f"Required extracted directory missing: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists() or destination.is_symlink():
        raise MigrationError(f"Staging destination already exists: {destination}")
    source.rename(destination)


def create_restore_tree(extracted, metadata, install, credentials, uid, gid, preserve_nas_credentials=False):
    extracted = Path(extracted)
    install = Path(install)
    install.mkdir(mode=0o700)
    mapping = {
        "norish-uploads": "norish/uploads", "norish-postgres": "norish/postgres",
        "norish-redis": "norish/redis", "guacamole": "guacamole/config",
        "firefly-mysql": "firefly/mysql", "firefly-redis": "firefly/redis",
        "firefly-upload": "firefly/upload", "proxy-data": "proxy/data",
        "proxy-certificates": "proxy/letsencrypt", "jellyfin-data": "jellyfin/data",
        "jellyfin-config": "jellyfin/config",
    }
    for source, target in mapping.items():
        move_directory(extracted / source, install / target)
    gitea = extracted / "gitea-source"
    old_config = (gitea / "gitea/conf/app.ini").read_text(encoding="utf-8")
    gitea_environment = container_environment(metadata, "gitea")
    if any(key.upper().startswith("GITEA__") for key in gitea_environment):
        raise MigrationError("Gitea uses environment configuration overrides; inspect them before restoring")
    secrets = parse_gitea_config(old_config)
    move_directory(gitea / "gitea", install / "gitea/data")
    move_directory(gitea / "git/repositories", install / "gitea/repositories")
    move_directory(gitea / "git/lfs", install / "gitea/data/lfs")
    private = install / "gitea/custom/conf"
    private.mkdir(parents=True, mode=0o700)
    for name, value in secrets.items():
        write_private(private / name, value + "\n")
    change_owner(install / "gitea", uid, gid)
    change_owner(install / "jellyfin", uid, gid)

    guacamole = container_environment(metadata, "Guacamole")
    old_uid = int(guacamole.get("PUID", "1026"))
    change_owner(install / "guacamole/config", uid, gid, old_uid=old_uid)

    private = install / "secrets"
    private.mkdir(mode=0o700)
    write_private(private / "guacamole.env", compose_env_line("PUID", str(uid)) + compose_env_line("PGID", str(gid)))
    norish = container_environment(metadata, "norish-norish-1")
    norish_db = container_environment(metadata, "norish-db-1")
    obscura = container_environment(metadata, "norish-obscura-1")
    if norish.get("OBSCURA_CDP_TOKEN") != obscura.get("OBSCURA_CDP_TOKEN"):
        raise MigrationError("Norish and Obscura tokens do not match")
    database_url = urlsplit(norish.get("DATABASE_URL", ""))
    if database_url.hostname != "db" or unquote(database_url.password or "") != norish_db.get("POSTGRES_PASSWORD"):
        raise MigrationError("Norish database URL does not match the restored database")
    if urlsplit(norish.get("REDIS_URL", "")).hostname != "redis" or urlsplit(norish.get("OBSCURA_ENDPOINT", "")).hostname != "obscura":
        raise MigrationError("Norish service endpoints do not match the target Compose network")
    write_private(private / "norish.env", selected_environment(norish,
        ("DATABASE_URL", "MASTER_KEY", "REDIS_URL", "OBSCURA_ENDPOINT", "OBSCURA_CDP_TOKEN"),
        ("DATABASE_URL", "MASTER_KEY", "REDIS_URL", "OBSCURA_ENDPOINT", "OBSCURA_CDP_TOKEN")))
    write_private(private / "norish-db.env", selected_environment(norish_db,
        ("POSTGRES_PASSWORD",), ("POSTGRES_PASSWORD",)))
    write_private(private / "norish-obscura.env", selected_environment(obscura,
        ("OBSCURA_CDP_TOKEN",), ("OBSCURA_CDP_TOKEN",)))
    firefly = container_environment(metadata, "Firefly")
    firefly_db = container_environment(metadata, "Firefly-DB")
    if firefly.get("DB_PASSWORD") != firefly_db.get("MYSQL_PASSWORD"):
        raise MigrationError("Firefly application and database passwords do not match")
    cron = next(item for item in metadata["containers"] if item["Name"].lstrip("/") == "Firefly-Cron")
    cron_command = " ".join(cron["Config"].get("Cmd") or [])
    cron_token = re.search(r"/api/v1/cron/([^\"\s]+)", cron_command)
    if not cron_token or cron_token.group(1) != firefly.get("STATIC_CRON_TOKEN"):
        raise MigrationError("Firefly cron command and application token do not match")
    write_private(private / "firefly.env", selected_environment(firefly,
        ("APP_KEY", "DB_PASSWORD", "REDIS_PASSWORD", "STATIC_CRON_TOKEN", "MAIL_USERNAME", "MAIL_PASSWORD"),
        ("APP_KEY", "DB_PASSWORD", "STATIC_CRON_TOKEN")))
    write_private(private / "firefly-db.env", selected_environment(firefly_db,
        ("MYSQL_ROOT_PASSWORD", "MYSQL_PASSWORD"), ("MYSQL_ROOT_PASSWORD", "MYSQL_PASSWORD")))
    write_private(private / "firefly-cron.env", selected_environment(firefly,
        ("STATIC_CRON_TOKEN",), ("STATIC_CRON_TOKEN",)))
    backup = container_environment(metadata, "bitwarden_backup")
    backup_keys = tuple(key for key in backup if key.startswith(("BW_", "CIFS_"))) + ("BITWARDEN_URL", "BACKUP_PASSWORD")
    write_private(private / "bitwarden-backup.env", selected_environment(backup, backup_keys,
        ("BITWARDEN_URL", "BACKUP_PASSWORD")))
    if not preserve_nas_credentials:
        write_private(private / "nas.creds", credentials_text(credentials))
    (install / "bitwarden-backup").mkdir()
    for project in ("gitea", "jellyfin", "proxy", "norish", "guacamole", "firefly", "bitwarden-backup"):
        os.chown(install / project, uid, gid)


def check_install_conflicts(source, destination):
    source = Path(source)
    destination = Path(destination)
    source_device = source.stat().st_dev
    for path in walk_paths(source):
        relative = path.relative_to(source)
        target = destination / relative
        if target.is_symlink():
            raise MigrationError(f"Refusing destination symlink: {target}")
        if path.is_dir() and not path.is_symlink():
            if target.exists() and not target.is_dir():
                raise MigrationError(f"Destination is not a directory: {target}")
            if target.exists() and target.stat().st_dev != source_device:
                raise MigrationError(f"Destination is on another filesystem: {target}")
        elif target.exists():
            raise MigrationError(f"Refusing to overwrite destination: {target}")


def install_tree(source, destination):
    source = Path(source)
    destination = Path(destination)
    check_install_conflicts(source, destination)
    for current, directories, files in os.walk(source, followlinks=False):
        current_path = Path(current)
        target_dir = destination / current_path.relative_to(source)
        if not target_dir.exists():
            target_dir.mkdir()
            shutil.copystat(current_path, target_dir, follow_symlinks=False)
            info = current_path.stat()
            os.chown(target_dir, info.st_uid, info.st_gid)
        for name in list(directories):
            path = current_path / name
            if path.is_symlink():
                files.append(name)
                directories.remove(name)
        for name in files:
            path = current_path / name
            target = target_dir / name
            if path.is_symlink():
                os.symlink(os.readlink(path), target)
                info = path.lstat()
                os.chown(target, info.st_uid, info.st_gid, follow_symlinks=False)
            elif path.is_file():
                os.link(path, target, follow_symlinks=False)
            else:
                raise MigrationError(f"Unsupported staged file type: {path}")


def copy_verified(source, destination, expected):
    with open(source, "rb") as incoming, open(destination, "xb") as output:
        shutil.copyfileobj(incoming, output, length=1024 * 1024)
        output.flush()
        os.fsync(output.fileno())
    if sha256_file(destination) != expected:
        raise MigrationError(f"Copied file checksum mismatch: {source}")


def validate_staged_compose(install, work, config_dir=Path("/etc/werkstatt/compose")):
    work.mkdir(mode=0o700)
    for name in ("proxy", "norish", "guacamole", "firefly", "bitwarden-backup"):
        config = json.loads((config_dir / f"{name}.json").read_text(encoding="utf-8"))
        for service in config["services"].values():
            for entry in service.get("env_file", []):
                path = Path(entry["path"])
                if path.parent != DESTINATION / "secrets" or entry.get("format") != "raw":
                    raise MigrationError(f"Unexpected Compose env-file configuration in {name}")
                entry["path"] = str(install / "secrets" / path.name)
        path = work / f"{name}.json"
        write_private(path, json.dumps(config))
        command("docker-compose", "-p", f"werkstatt-{name}", "-f", str(path), "config", "--quiet")


def target_units_inactive():
    units = ("gitea", "jellyfin", "werkstatt-proxy", "werkstatt-norish", "werkstatt-guacamole",
             "werkstatt-firefly", "werkstatt-bitwarden-backup")
    for unit in units:
        result = command("systemctl", "show", f"{unit}.service", "--property=ActiveState", "--value", capture=True, check=False)
        if result.returncode != 0 or result.stdout.strip() not in {"inactive", "failed"}:
            raise MigrationError(f"Target service is active or unavailable: {unit}")
    for project in ("gitea", "jellyfin", "proxy", "norish", "guacamole", "firefly", "bitwarden-backup"):
        marker = DESTINATION / project / ".ready"
        if marker.exists() or marker.is_symlink():
            raise MigrationError(f"Target readiness marker already exists: {marker}")


def start_services():
    if not DESTINATION.is_dir() or DESTINATION.is_symlink():
        raise MigrationError("The services directory is missing or is a symlink")

    def checked_path(relative):
        path = DESTINATION
        for component in Path(relative).parts:
            path = path / component
            if path.is_symlink():
                raise MigrationError(f"Unsafe symlink in restored path: {path}")
        return path

    for relative in SERVICE_REQUIRED_DIRS:
        path = checked_path(relative)
        if not path.is_dir():
            raise MigrationError(f"Restored directory missing or unsafe: {path}")
    for relative in SERVICE_REQUIRED_FILES:
        path = checked_path(relative)
        if not path.is_file() or path.stat().st_size == 0:
            raise MigrationError(f"Restored file missing or empty: {path}")
    for project in SERVICE_PROJECTS:
        marker = checked_path(f"{project}/.ready")
        if marker.exists() and not marker.is_file():
            raise MigrationError(f"Unsafe readiness marker: {marker}")
    for name in ("proxy", "norish", "guacamole", "firefly", "bitwarden-backup"):
        command(
            "docker-compose", "-p", f"werkstatt-{name}", "-f",
            str(COMPOSE_DIRECTORY / f"{name}.json"), "config", "--quiet",
        )
    require_confirmation(
        "Enable and start Gitea, Jellyfin, proxy, Norish, Guacamole and "
        "Firefly? This may upgrade application databases. The old services "
        "must remain stopped.", "START SERVICES"
    )
    for project in SERVICE_PROJECTS:
        marker = DESTINATION / project / ".ready"
        if not marker.exists():
            with open(marker, "x", encoding="utf-8"):
                pass
    command("systemctl", "reset-failed", *START_UNITS)
    failed = []
    for unit in START_UNITS:
        result = command("systemctl", "start", unit, check=False)
        active = command("systemctl", "is-active", "--quiet", unit, check=False)
        if result.returncode or active.returncode:
            failed.append(unit)
    if failed:
        raise MigrationError(
            f"Some services did not start: {', '.join(failed)}. "
            "Check their journals; NAS backup remains intact"
        )
    print("Services started. Check container health, logins and data.")
    print("Bitwarden backup remains manual; migrate Home Assistant separately.")


def restore_snapshot(snapshot, share, credentials):
    manifest = load_manifest(snapshot)
    if manifest.get("source") != "ubuntu2004":
        raise MigrationError("Snapshot was not created from ubuntu2004")
    verify_snapshot(snapshot, manifest, check_mount=share)
    if not DESTINATION.is_dir() or DESTINATION.is_symlink():
        raise MigrationError("The activated werkstatt services directory is missing or is a symlink")
    target_units_inactive()
    account = pwd.getpwnam("jonas")
    users_gid = grp.getgrnam("users").gr_gid
    required = sum((Path(snapshot) / relative).stat().st_size for relative in RESTORE_ARCHIVES.values())
    expanded = 0
    for relative in RESTORE_ARCHIVES.values():
        with tarfile.open(Path(snapshot) / relative, "r:") as archive:
            expanded += sum(member.size for member in archive if member.isfile())
    required += expanded + (Path(snapshot) / "docker-images.tar").stat().st_size * 2 + 1024**3
    available = shutil.disk_usage(DESTINATION).free
    if available < required:
        raise MigrationError(f"Target space is insufficient: need approximately {required} bytes, have {available}")
    stage = Path(tempfile.mkdtemp(prefix=".migration-restore-", dir=DESTINATION))
    stage.chmod(0o700)
    print(f"Restore staging directory: {stage}", flush=True)
    archives = stage / "archives"
    archives.mkdir(mode=0o700)
    extracted = stage / "extracted"
    extracted.mkdir(mode=0o700)
    metadata_file = stage / "source-state.json"
    copy_verified(Path(snapshot) / "source-state.json", metadata_file, manifest["files"]["source-state.json"])
    metadata = json.loads(metadata_file.read_text(encoding="utf-8"))
    for name, relative in RESTORE_ARCHIVES.items():
        require_nas_mount(share)
        local_archive = archives / f"{name}.tar"
        print(f"Staging {relative}", flush=True)
        copy_verified(Path(snapshot) / relative, local_archive, manifest["files"][relative])
        safe_extract(local_archive, extracted / name)
    existing_nas = DESTINATION / "secrets/nas.creds"
    if existing_nas.is_symlink() or (existing_nas.exists() and not existing_nas.is_file()):
        raise MigrationError("Existing NAS credentials are not a regular file")
    install = stage / "install"
    create_restore_tree(extracted, metadata, install, credentials, account.pw_uid, users_gid, existing_nas.is_file())
    validate_staged_compose(install, stage / "compose-validation")
    check_install_conflicts(install, DESTINATION)
    target_units_inactive()
    require_confirmation(
        "All selected files are staged and verified. Installation will not overwrite existing files. "
        "Starting native Gitea later upgrades a copy of its database; the NAS snapshot remains unchanged.", "INSTALL"
    )
    install_tree(install, DESTINATION)
    print("Restored files and secrets without overwriting existing data.")
    print(f"The verified NAS snapshot and staging directory remain available: {snapshot.name}, {stage}")
    existing_images = command("docker", "image", "ls", "-q", "--no-trunc", capture=True).stdout.split()
    if existing_images:
        print("Docker already has images; not loading saved tags over them. Compose may pull pinned images from the registry.")
    else:
        print("Loading the saved Docker images into the empty image store.", flush=True)
        command("docker", "image", "load", "--input", str(Path(snapshot) / "docker-images.tar"))
    start_services()
    answer = input("Enroll the new Tailscale node now? [Y/n]: ").strip().lower()
    if answer in {"", "y", "yes"}:
        command("tailscale", "up")
        command("systemctl", "restart", "werkstatt-tailscale-serve")
    else:
        print("Later run sudo tailscale up and restart werkstatt-tailscale-serve.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", nargs="?", choices=("backup", "restore", "start"),
                        help="default: backup on ubuntu2004, restore on werkstatt")
    parser.add_argument("--snapshot", help="restore a specific complete snapshot by its directory name")
    arguments = parser.parse_args(argv)
    if os.geteuid() != 0:
        raise MigrationError("Run this script as root using sudo")
    hostname = socket.gethostname().split(".", 1)[0]
    expected_mode = {"ubuntu2004": "backup", "werkstatt": "restore"}.get(hostname)
    mode = arguments.mode or expected_mode
    if expected_mode is None or (expected_mode == "backup" and mode != "backup") or (expected_mode == "restore" and mode not in {"restore", "start"}):
        raise MigrationError("Run backup only on ubuntu2004 and restore/start only on werkstatt")
    if arguments.snapshot and mode != "restore":
        raise MigrationError("--snapshot is only valid in restore mode")
    if mode == "start":
        require_commands(("docker-compose", "systemctl"))
        with exclusive_lock():
            start_services()
        return
    if not hasattr(tarfile, "data_filter"):
        raise MigrationError("Python 3.12 or newer is required for safe tar extraction")
    require_commands(("docker", "tar", "mount", "mount.cifs", "umount", "findmnt", "systemctl", "du"))
    if mode == "restore":
        require_commands(("docker-compose", "tailscale"))
    print(f"Using {NAS_SHARE}/{NAS_FOLDER}. The backup contains plaintext secrets.")
    credentials = ask_credentials()
    with exclusive_lock(), mounted_nas(credentials, read_only=mode == "restore") as share:
        if mode == "backup":
            create_snapshot(share)
        else:
            snapshot = select_snapshot(share, arguments.snapshot)
            restore_snapshot(snapshot, share, credentials)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted. Source services may remain stopped; incomplete snapshots are not marked COMPLETE.", file=sys.stderr)
        sys.exit(130)
    except (MigrationError, OSError, ValueError, KeyError, subprocess.CalledProcessError, tarfile.TarError) as error:
        print(f"Migration failed: {error}", file=sys.stderr)
        print("Do not format the source. Keep all snapshots and staging files for recovery.", file=sys.stderr)
        sys.exit(1)