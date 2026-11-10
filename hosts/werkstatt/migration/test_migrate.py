import importlib.util
import contextlib
import io
import json
import os
import subprocess
import tarfile
import tempfile
import types
import unittest
from pathlib import Path
from unittest import mock


SPEC = importlib.util.spec_from_file_location("migrate", Path(__file__).with_name("migrate.py"))
migrate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(migrate)


class MigrationTests(unittest.TestCase):
    @staticmethod
    def create_service_fixture(root):
        for relative in migrate.SERVICE_REQUIRED_DIRS:
            (root / relative).mkdir(parents=True, exist_ok=True)
        for relative in migrate.SERVICE_REQUIRED_FILES:
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("restored")

    @staticmethod
    def example_metadata():
        def container(name, values, cmd=None):
            return {"Name": "/" + name, "Config": {"Env": [f"{key}={value}" for key, value in values.items()], "Cmd": cmd or []}}
        return {"containers": [
            container("Guacamole", {"PUID": str(os.getuid())}),
            container("norish-norish-1", {"DATABASE_URL": "postgres://postgres:database@db/norish", "MASTER_KEY": "key", "REDIS_URL": "redis://redis", "OBSCURA_ENDPOINT": "http://obscura", "OBSCURA_CDP_TOKEN": "token"}),
            container("norish-db-1", {"POSTGRES_PASSWORD": "database"}),
            container("norish-obscura-1", {"OBSCURA_CDP_TOKEN": "token"}),
            container("Firefly", {"APP_KEY": "app", "DB_PASSWORD": "database", "STATIC_CRON_TOKEN": "cron"}),
            container("Firefly-DB", {"MYSQL_PASSWORD": "database", "MYSQL_ROOT_PASSWORD": "root"}),
            container("Firefly-Cron", {}, ["wget http://firefly:8080/api/v1/cron/cron"]),
            container("gitea", {}),
            container("bitwarden_backup", {"BITWARDEN_URL": "https://example.test", "BACKUP_PASSWORD": "backup", "BW_USER_1": "user"}),
        ]}

    def test_compose_env_rejects_multiline(self):
        with self.assertRaises(migrate.MigrationError):
            migrate.compose_env_line("TOKEN", "one\ntwo")

    def test_start_reuses_existing_markers_and_starts_services(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.create_service_fixture(root)
            marker = root / "gitea/.ready"
            marker.write_text("existing")
            calls = []
            def fake_command(*arguments, **kwargs):
                calls.append(arguments)
                return subprocess.CompletedProcess(arguments, 0)
            with mock.patch.object(migrate, "DESTINATION", root), \
                 mock.patch.object(migrate, "command", side_effect=fake_command), \
                  mock.patch.object(migrate, "verify_service_endpoints"), \
                 mock.patch.object(migrate, "require_confirmation") as confirmation:
                migrate.start_services()
            self.assertEqual(marker.read_text(), "existing")
            self.assertTrue(all((root / project / ".ready").is_file() for project in migrate.SERVICE_PROJECTS))
            self.assertIn(("systemctl", "reset-failed", *migrate.START_UNITS), calls)
            self.assertEqual([call[2] for call in calls if call[:2] == ("systemctl", "start")], list(migrate.START_UNITS))
            confirmation.assert_called_once()

    def test_start_rejects_missing_data_before_creating_markers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.create_service_fixture(root)
            (root / "gitea/data/gitea.db").unlink()
            with mock.patch.object(migrate, "DESTINATION", root), mock.patch.object(migrate, "command") as run:
                with self.assertRaisesRegex(migrate.MigrationError, "Restored file missing"):
                    migrate.start_services()
            self.assertFalse((root / "gitea/.ready").exists())
            run.assert_not_called()

    def test_endpoint_check_rejects_disconnected_container(self):
        def fake_inspect(operation, name):
            network, port, host_port = migrate.APP_ENDPOINTS[name]
            networks = {} if name == "werkstatt-proxy-app-1" else {network: {}}
            return [{"State": {"Status": "running"}, "NetworkSettings": {
                "Networks": networks, "Ports": {port: [{"HostPort": host_port}]},
            }}]
        with mock.patch.object(migrate, "docker_json", side_effect=fake_inspect), \
             mock.patch.object(migrate.socket, "create_connection", return_value=contextlib.nullcontext()):
            with self.assertRaisesRegex(migrate.MigrationError, "werkstatt-proxy-app-1 is not running on"):
                migrate.verify_service_endpoints()

    def test_endpoint_check_reports_missing_native_listener(self):
        def fake_inspect(operation, name):
            network, port, host_port = migrate.APP_ENDPOINTS[name]
            return [{"State": {"Status": "running"}, "NetworkSettings": {
                "Networks": {network: {}}, "Ports": {port: [{"HostPort": host_port}]},
            }}]
        with mock.patch.object(migrate, "docker_json", side_effect=fake_inspect), \
             mock.patch.object(migrate.socket, "create_connection", side_effect=OSError("connection refused")):
            with self.assertRaisesRegex(migrate.MigrationError, "Gitea is not listening"):
                migrate.verify_service_endpoints()

    def test_start_reports_failures_after_trying_all_services(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.create_service_fixture(root)
            calls = []
            def fake_command(*arguments, **kwargs):
                calls.append(arguments)
                failed = arguments[:2] == ("systemctl", "start") and arguments[2] == "werkstatt-firefly"
                return subprocess.CompletedProcess(arguments, 1 if failed else 0)
            with mock.patch.object(migrate, "DESTINATION", root), \
                 mock.patch.object(migrate, "command", side_effect=fake_command), \
                 mock.patch.object(migrate, "require_confirmation"):
                with self.assertRaisesRegex(migrate.MigrationError, "werkstatt-firefly"):
                    migrate.start_services()
            self.assertEqual([call[2] for call in calls if call[:2] == ("systemctl", "start")], list(migrate.START_UNITS))
            self.assertNotIn(("systemctl", "start", "werkstatt-bitwarden-backup"), calls)

    def test_start_rejects_symlinked_project(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.create_service_fixture(root)
            (root / "proxy/data").rmdir()
            (root / "proxy/data").symlink_to(root / "jellyfin/data")
            with mock.patch.object(migrate, "DESTINATION", root):
                with self.assertRaisesRegex(migrate.MigrationError, "Unsafe symlink"):
                    migrate.start_services()

    def test_start_declined_does_not_create_markers(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.create_service_fixture(root)
            with mock.patch.object(migrate, "DESTINATION", root), \
                 mock.patch.object(migrate, "command", return_value=subprocess.CompletedProcess([], 0)), \
                 mock.patch.object(migrate, "require_confirmation", side_effect=migrate.MigrationError("declined")):
                with self.assertRaisesRegex(migrate.MigrationError, "declined"):
                    migrate.start_services()
            self.assertFalse(any((root / project / ".ready").exists() for project in migrate.SERVICE_PROJECTS))

    def test_start_mode_does_not_mount_nas(self):
        with mock.patch.object(migrate.os, "geteuid", return_value=0), \
             mock.patch.object(migrate.socket, "gethostname", return_value="werkstatt"), \
             mock.patch.object(migrate, "require_commands"), \
             mock.patch.object(migrate, "exclusive_lock", return_value=contextlib.nullcontext()), \
             mock.patch.object(migrate, "ask_credentials") as credentials, \
             mock.patch.object(migrate, "mounted_nas") as nas, \
             mock.patch.object(migrate, "start_services") as start:
            migrate.main(["start"])
        credentials.assert_not_called()
        nas.assert_not_called()
        start.assert_called_once()

    def test_compose_env_round_trip(self):
        values = ["dollar$ quote' backslash\\ backslash-quote\\' trailing\\", "#starts-with-hash", '"quoted"', "  spaces  "]
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "compose.json").write_text(json.dumps({
                "services": {"test": {"image": "example", "env_file": [{"path": str(root / "secret.env"), "format": "raw"}]}}
            }))
            for value in values:
                with self.subTest(value=value):
                    (root / "secret.env").write_text(migrate.compose_env_line("TOKEN", value))
                    output = subprocess.check_output([
                        "docker", "compose", "-f", str(root / "compose.json"), "config", "--format", "json"
                    ], text=True)
                    rendered = json.loads(output)["services"]["test"]["environment"]["TOKEN"]
                    self.assertEqual(rendered.replace("$$", "$"), value)

    def test_validate_staged_compose_with_real_yaml(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            secrets = root / "install/secrets"
            secrets.mkdir(parents=True)
            for name in ("norish", "norish-db", "norish-obscura", "guacamole", "firefly", "firefly-db", "firefly-cron", "bitwarden-backup"):
                (secrets / f"{name}.env").write_text("TOKEN=example\n")
            work = root / "validation"
            migrate.validate_staged_compose(root / "install", work, Path(__file__).parent.parent / "containers")
            config = json.loads((work / "firefly.json").read_text())
            self.assertEqual(config["services"]["cron"]["env_file"][0]["path"], str(secrets / "firefly-cron.env"))
            self.assertIn("$$STATIC_CRON_TOKEN", config["services"]["cron"]["command"][2])
            rendered = subprocess.check_output([
                "docker-compose", "-p", "werkstatt-firefly", "-f", str(work / "firefly.json"),
                "config", "--no-env-resolution", "--format", "json",
            ], text=True)
            self.assertIn("$STATIC_CRON_TOKEN", json.loads(rendered)["services"]["cron"]["command"][2])

    def test_validate_staged_compose_rejects_unexpected_env_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "proxy.yaml").write_text(json.dumps({
                "services": {"app": {"image": "example", "env_file": [{"path": "/tmp/unexpected.env", "format": "raw"}]}}
            }))
            with self.assertRaisesRegex(migrate.MigrationError, "Unexpected Compose env-file"):
                migrate.validate_staged_compose(root / "install", root / "validation", root)

    def test_empty_gitea_key_uses_original_fallback(self):
        config = "[security]\nSECRET_KEY=\nINTERNAL_TOKEN=one\n[oauth2]\nJWT_SECRET=two\n[server]\nLFS_JWT_SECRET=three\n"
        self.assertEqual(migrate.parse_gitea_config(config)["secret_key"], migrate.GITEA_LEGACY_SECRET)

    def test_sha256_detects_corruption(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "archive"
            path.write_bytes(b"private migration data")
            original = migrate.sha256_file(path)
            path.write_bytes(b"corrupted migration data")
            self.assertNotEqual(original, migrate.sha256_file(path))

    def test_archive_round_trip(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "data").write_bytes(b"database bytes")
            (source / "data").chmod(0o660)
            os.setxattr(source / "data", "user.migration-test", b"metadata")
            archive = root / "archive.tar"
            digest = migrate.archive_directory(source, archive)
            self.assertEqual(digest, migrate.sha256_file(archive))
            migrate.safe_extract(archive, root / "restore")
            self.assertEqual((root / "restore" / "data").read_bytes(), b"database bytes")
            self.assertEqual((root / "restore" / "data").stat().st_mode & 0o777, 0o660)
            self.assertEqual(os.getxattr(root / "restore" / "data", "user.migration-test"), b"metadata")

    def test_rejects_tar_path_traversal(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            archive = root / "unsafe.tar"
            with tarfile.open(archive, "w") as output:
                member = tarfile.TarInfo("../outside")
                member.size = 1
                output.addfile(member, io.BytesIO(b"x"))
            with self.assertRaises(tarfile.FilterError):
                migrate.safe_extract(archive, root / "extract")
            self.assertFalse((root / "outside").exists())

    def test_failed_unmount_preserves_share_and_original_error(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "mount-wrapper"
            root.mkdir()
            def fake_command(*arguments, **kwargs):
                if arguments[0] == "findmnt":
                    return subprocess.CompletedProcess(arguments, 0, stdout=f"{migrate.NAS_SHARE} cifs\n")
                if arguments[0] == "umount":
                    return subprocess.CompletedProcess(arguments, 1)
                return subprocess.CompletedProcess(arguments, 0)
            with mock.patch.object(migrate.tempfile, "mkdtemp", return_value=str(root)), \
                 mock.patch.object(migrate.os.path, "ismount", return_value=True), \
                 mock.patch.object(migrate, "command", side_effect=fake_command):
                with self.assertRaisesRegex(RuntimeError, "original failure"):
                    with migrate.mounted_nas({"username": "user", "password": "pass", "domain": ""}, False) as mount:
                        (mount / "keep").write_text("preserve")
                        raise RuntimeError("original failure")
            self.assertEqual((root / "share" / "keep").read_text(), "preserve")
            self.assertFalse((root / "nas.creds").exists())

    def test_incomplete_or_corrupt_snapshot_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary)
            with self.assertRaises(migrate.MigrationError):
                migrate.load_manifest(snapshot)
            (snapshot / "manifest.json").write_text('{"format":1,"files":{}}')
            (snapshot / "COMPLETE").write_text("0" * 64)
            with self.assertRaisesRegex(migrate.MigrationError, "checksum"):
                migrate.load_manifest(snapshot)

    def test_snapshot_path_traversal_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            snapshot = Path(temporary)
            (snapshot / "manifest.json").write_text(json.dumps({"format": 1, "files": {"../outside": "0" * 64}}))
            (snapshot / "COMPLETE").write_text(migrate.sha256_file(snapshot / "manifest.json"))
            with self.assertRaisesRegex(migrate.MigrationError, "Unsafe snapshot path"):
                migrate.load_manifest(snapshot)

    def test_install_refuses_overwrite_before_copying(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "first").write_text("new")
            (source / "existing").write_text("replacement")
            (destination / "existing").write_text("original")
            with self.assertRaisesRegex(migrate.MigrationError, "overwrite"):
                migrate.install_tree(source, destination)
            self.assertEqual((destination / "existing").read_text(), "original")
            self.assertFalse((destination / "first").exists())

    def test_install_refuses_destination_symlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source"
            destination = root / "destination"
            source.mkdir()
            destination.mkdir()
            (source / "folder").mkdir()
            (destination / "folder").symlink_to(root)
            with self.assertRaisesRegex(migrate.MigrationError, "symlink"):
                migrate.install_tree(source, destination)

    def test_builds_staged_service_data_and_secrets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            extracted = root / "extracted"
            extracted.mkdir()
            for name in migrate.RESTORE_ARCHIVES:
                (extracted / name).mkdir()
            gitea = extracted / "gitea-source"
            (gitea / "gitea/conf").mkdir(parents=True)
            (gitea / "gitea/gitea.db").write_bytes(b"database")
            (gitea / "gitea/conf/app.ini").write_text(
                "[security]\nSECRET_KEY=\nINTERNAL_TOKEN=one\n"
                "[oauth2]\nJWT_SECRET=two\n[server]\nLFS_JWT_SECRET=three\n"
            )
            (gitea / "git/repositories").mkdir(parents=True)
            (gitea / "git/lfs").mkdir()
            metadata = self.example_metadata()
            install = root / "install"
            migrate.create_restore_tree(extracted, metadata, install,
                {"username": "nas", "password": "nas-secret", "domain": ""}, os.getuid(), os.getgid())
            self.assertEqual((install / "gitea/data/gitea.db").read_bytes(), b"database")
            self.assertEqual((install / "gitea/custom/conf/secret_key").read_text().strip(), migrate.GITEA_LEGACY_SECRET)
            self.assertEqual((install / "secrets/firefly-cron.env").read_text(), "STATIC_CRON_TOKEN=cron\n")
            self.assertEqual((install / "secrets/guacamole.env").read_text(), f"PUID={os.getuid()}\nPGID={os.getgid()}\n")
            self.assertEqual((install / "secrets/nas.creds").stat().st_mode & 0o777, 0o600)

    def test_jellyfin_legacy_transcode_path_is_migrated_atomically(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "encoding.xml"
            config.write_text('<?xml version="1.0"?><EncodingOptions><TranscodingTempPath>/var/lib/jellyfin/transcodes</TranscodingTempPath><Other>keep</Other></EncodingOptions>')
            backup = root / "backup.xml"
            os.link(config, backup)
            with mock.patch.object(migrate, "DESTINATION", root / "services"):
                self.assertTrue(migrate.migrate_jellyfin_transcode_path(root))
            self.assertIn(str(root / "services/jellyfin/cache/transcodes"), config.read_text())
            self.assertIn("/var/lib/jellyfin/transcodes", backup.read_text())
            self.assertIn("<Other>keep</Other>", config.read_text())
            self.assertFalse(migrate.migrate_jellyfin_transcode_path(root))

    def test_jellyfin_custom_transcode_path_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            config = root / "encoding.xml"
            original = "<EncodingOptions><TranscodingTempPath>/custom/transcodes</TranscodingTempPath></EncodingOptions>"
            config.write_text(original)
            self.assertFalse(migrate.migrate_jellyfin_transcode_path(root))
            self.assertEqual(config.read_text(), original)

    def test_token_mismatch_is_rejected(self):
        with self.assertRaises(migrate.MigrationError):
            migrate.selected_environment({}, ("TOKEN",), ("TOKEN",))

    def test_changed_source_image_is_rejected(self):
        containers = [{"Name": "/app", "Image": "image-id"}]
        images = [{"Id": "image-id", "RepoDigests": ["example@sha256:" + "b" * 64]}]
        with mock.patch.object(migrate, "EXPECTED_DIGESTS", {"app": "a" * 64}):
            with self.assertRaisesRegex(migrate.MigrationError, "Source image changed"):
                migrate.validate_source_images(containers, images)

    def test_interrupted_export_has_no_complete_marker(self):
        with tempfile.TemporaryDirectory() as temporary:
            share = Path(temporary)
            metadata = {"containers": [], "local_volumes": {}, "images": [], "external_volumes": [], "volumes": []}
            with mock.patch.object(migrate, "require_confirmation"), \
                 mock.patch.object(migrate, "inspect_source", return_value=metadata), \
                 mock.patch.object(migrate, "require_nas_mount"), \
                 mock.patch.object(migrate, "estimate_snapshot_size", return_value=0), \
                 mock.patch.object(migrate, "stop_source", side_effect=migrate.MigrationError("stop failed")):
                with self.assertRaisesRegex(migrate.MigrationError, "stop failed"):
                    migrate.create_snapshot(share)
            snapshots = list((share / migrate.NAS_FOLDER).iterdir())
            self.assertEqual(len(snapshots), 1)
            self.assertFalse((snapshots[0] / "COMPLETE").exists())

    def test_complete_export_manifest_verifies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            share = root / "share"
            share.mkdir()
            volume = root / "volume"
            folder = root / "folder"
            volume.mkdir()
            folder.mkdir()
            (volume / "data").write_text("volume-data")
            (folder / "data").write_text("folder-data")
            metadata = {
                "containers": [{"Name": "/example", "Id": "container-id"}],
                "local_volumes": {"example": str(volume)},
                "volumes": [{"Name": "example"}],
                "images": [{"Id": "image-id", "RepoTags": ["example:latest"]}],
                "external_volumes": [],
            }
            def fake_archive_command(arguments, destination):
                with tarfile.open(destination, "w") as archive:
                    member = tarfile.TarInfo("data")
                    member.size = 1
                    archive.addfile(member, io.BytesIO(b"x"))
                return migrate.sha256_file(destination)
            with mock.patch.object(migrate, "require_confirmation"), \
                 mock.patch.object(migrate, "inspect_source", return_value=metadata), \
                 mock.patch.object(migrate, "require_nas_mount"), \
                 mock.patch.object(migrate, "estimate_snapshot_size", return_value=0), \
                 mock.patch.object(migrate, "stop_source"), \
                 mock.patch.object(migrate, "assert_source_quiet"), \
                 mock.patch.object(migrate, "archive_command", side_effect=fake_archive_command), \
                 mock.patch.object(migrate, "SOURCE_FOLDERS", {"sample": str(folder)}), \
                 mock.patch.object(migrate, "REQUIRED_FOLDERS", {"sample"}), \
                 mock.patch.object(migrate, "REQUIRED_VOLUMES", {"example"}):
                snapshot = migrate.create_snapshot(share)
                manifest = migrate.load_manifest(snapshot)
                migrate.verify_snapshot(snapshot, manifest)
            self.assertTrue((snapshot / "COMPLETE").is_file())

    def test_end_to_end_restore_from_fixture(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            snapshot = root / "snapshot"
            snapshot.mkdir()
            (snapshot / "volumes").mkdir()
            (snapshot / "system").mkdir()
            source = root / "source"
            source.mkdir()
            checksums = {}
            for name in migrate.REQUIRED_VOLUMES:
                folder = source / name
                folder.mkdir()
                if name == "gitea_gitea":
                    (folder / "gitea/conf").mkdir(parents=True)
                    (folder / "gitea/gitea.db").write_bytes(b"gitea database")
                    (folder / "gitea/conf/app.ini").write_text(
                        "[security]\nSECRET_KEY=\nINTERNAL_TOKEN=one\n"
                        "[oauth2]\nJWT_SECRET=two\n[server]\nLFS_JWT_SECRET=three\n")
                    (folder / "git/repositories").mkdir(parents=True)
                    (folder / "git/lfs").mkdir()
                else:
                    (folder / "data").write_text(name)
                relative = f"volumes/{name}.tar"
                checksums[relative] = migrate.archive_directory(folder, snapshot / relative)
            for name in migrate.REQUIRED_FOLDERS:
                folder = source / name
                folder.mkdir()
                (folder / "data").write_text(name)
                relative = f"system/{name}.tar"
                checksums[relative] = migrate.archive_directory(folder, snapshot / relative)
            with tarfile.open(snapshot / "docker-images.tar", "w"):
                pass
            checksums["docker-images.tar"] = migrate.sha256_file(snapshot / "docker-images.tar")
            (snapshot / "source-state.json").write_text(json.dumps(self.example_metadata()))
            checksums["source-state.json"] = migrate.sha256_file(snapshot / "source-state.json")
            (snapshot / "manifest.json").write_text(json.dumps({"format": 1, "source": "ubuntu2004", "files": checksums}))
            (snapshot / "COMPLETE").write_text(migrate.sha256_file(snapshot / "manifest.json"))
            destination = root / "services"
            destination.mkdir()
            (destination / "untouched").write_text("existing")
            config_dir = root / "compose"
            config_dir.mkdir()
            env_names = {"norish": "norish.env", "guacamole": "guacamole.env", "firefly": "firefly.env", "bitwarden-backup": "bitwarden-backup.env"}
            for name in ("proxy", "norish", "guacamole", "firefly", "bitwarden-backup"):
                service = {"image": "example"}
                if name in env_names:
                    service["env_file"] = [{"path": str(destination / "secrets" / env_names[name]), "format": "raw"}]
                (config_dir / f"{name}.yaml").write_text(json.dumps({"services": {name: service}}))
            original_validation = migrate.validate_staged_compose
            def fake_command(*arguments, **kwargs):
                if arguments[0] in {"docker-compose", "tar"}:
                    return subprocess.run(arguments, text=True, check=True, capture_output=kwargs.get("capture", False))
                return subprocess.CompletedProcess(arguments, 0, stdout="existing-image\n")
            with mock.patch.object(migrate, "DESTINATION", destination), \
                  mock.patch.object(migrate, "COMPOSE_DIRECTORY", config_dir), \
                 mock.patch.object(migrate, "require_nas_mount"), \
                 mock.patch.object(migrate, "target_units_inactive"), \
                 mock.patch.object(migrate, "verify_service_endpoints"), \
                 mock.patch.object(migrate, "require_confirmation"), \
                 mock.patch.object(migrate, "command", side_effect=fake_command), \
                 mock.patch.object(migrate.pwd, "getpwnam", return_value=types.SimpleNamespace(pw_uid=os.getuid())), \
                 mock.patch.object(migrate.grp, "getgrnam", return_value=types.SimpleNamespace(gr_gid=os.getgid())), \
                 mock.patch.object(migrate, "validate_staged_compose", side_effect=lambda install, work: original_validation(install, work, config_dir)), \
                 mock.patch("builtins.input", return_value="n"):
                migrate.restore_snapshot(snapshot, root, {"username": "nas", "password": "password", "domain": ""})
            self.assertEqual((destination / "gitea/data/gitea.db").read_bytes(), b"gitea database")
            self.assertEqual((destination / "untouched").read_text(), "existing")
            self.assertEqual((destination / "secrets/firefly-cron.env").read_text(), "STATIC_CRON_TOKEN=cron\n")
            self.assertTrue((destination / "norish/.ready").is_file())


if __name__ == "__main__":
    unittest.main()