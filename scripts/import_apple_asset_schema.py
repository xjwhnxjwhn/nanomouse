#!/usr/bin/env python3
"""Import the CloudKit schema required by Apple asset distribution."""

from __future__ import annotations

import argparse
import re
import subprocess
import tempfile
from datetime import datetime
from pathlib import Path


CONTAINER_ID = "iCloud.com.XiangqingZHANG.nanomouse"
RECORD_TYPE = "NanomouseAssetPackage"
REPO_ROOT = Path(__file__).resolve().parent.parent
IOS_PROJECT = REPO_ROOT / "ios" / "Hamster.xcodeproj"
IOS_SCHEME = "Hamster"
RECORD_TYPE_FRAGMENT_FILE = REPO_ROOT / "cloudkit" / "nanomouse-asset-record-type.ckdb"
DEFAULT_BACKUP_DIR = Path("/tmp/nanomouse-cloudkit-schema-backups")


def read_development_team_from_xcodebuild() -> str | None:
    try:
        result = subprocess.run(
            [
                "xcodebuild",
                "-project",
                str(IOS_PROJECT),
                "-scheme",
                IOS_SCHEME,
                "-showBuildSettings",
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except (FileNotFoundError, subprocess.CalledProcessError):
        return None

    match = re.search(r"^\s*DEVELOPMENT_TEAM\s*=\s*(\S+)\s*$", result.stdout, re.MULTILINE)
    return match.group(1) if match else None


def read_development_team_from_pbxproj() -> str | None:
    pbxproj = IOS_PROJECT / "project.pbxproj"
    if not pbxproj.exists():
        return None
    match = re.search(r"DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]+);", pbxproj.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def resolve_team_id(args: argparse.Namespace) -> str:
    if args.team_id:
        return args.team_id
    team_id = read_development_team_from_xcodebuild() or read_development_team_from_pbxproj()
    if not team_id:
        raise SystemExit("未能从 Xcode 工程读取 DEVELOPMENT_TEAM，请手动传入 --team-id。")
    return team_id


def cktool_command(args: argparse.Namespace, subcommand: str) -> list[str]:
    command = ["xcrun", "cktool", subcommand]
    if args.token:
        command.extend(["--token", args.token])
    return command


def run(command: list[str]) -> None:
    redacted = command.copy()
    for index, item in enumerate(redacted[:-1]):
        if item == "--token":
            redacted[index + 1] = "***"
    print("+", " ".join(redacted))
    subprocess.run(command, check=True)


def capture(command: list[str]) -> str:
    redacted = command.copy()
    for index, item in enumerate(redacted[:-1]):
        if item == "--token":
            redacted[index + 1] = "***"
    print("+", " ".join(redacted))
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    return result.stdout


def export_current_schema(args: argparse.Namespace) -> str:
    return capture(
        cktool_command(args, "export-schema")
        + [
            "--team-id",
            args.team_id,
            "--container-id",
            args.container_id,
            "--environment",
            args.environment,
        ]
    )


def schema_contains_record_type(schema: str, record_type: str) -> bool:
    return re.search(rf"\bRECORD\s+TYPE\s+{re.escape(record_type)}\s*\(", schema) is not None


def merged_schema(schema: str, record_type_fragment: str) -> str:
    schema = schema.rstrip()
    if not schema.startswith("DEFINE SCHEMA"):
        raise SystemExit("导出的 CloudKit schema 格式异常：缺少 DEFINE SCHEMA。")
    return f"{schema}\n\n{record_type_fragment.rstrip()}\n"


def write_schema_backups(args: argparse.Namespace, current_schema: str, schema_text: str) -> None:
    if args.no_backup:
        return
    backup_dir = args.backup_dir
    if not backup_dir.is_absolute():
        backup_dir = (REPO_ROOT / backup_dir).resolve()
    backup_dir.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    current_path = backup_dir / f"{args.environment}-current-{timestamp}.ckdb"
    merged_path = backup_dir / f"{args.environment}-merged-{timestamp}.ckdb"
    current_path.write_text(current_schema, encoding="utf-8")
    merged_path.write_text(schema_text, encoding="utf-8")
    print(f"Current schema backup: {current_path}")
    print(f"Merged schema backup: {merged_path}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team-id", help="Apple Developer Team ID. Omit to read DEVELOPMENT_TEAM from ios/Hamster.xcodeproj.")
    parser.add_argument("--container-id", default=CONTAINER_ID)
    parser.add_argument("--environment", choices=["development", "production"], default="development")
    parser.add_argument("--record-type-fragment", type=Path, default=RECORD_TYPE_FRAGMENT_FILE)
    parser.add_argument("--token", help="CloudKit management token. Omit to use cktool keychain/env lookup.")
    parser.add_argument("--skip-validate", action="store_true")
    parser.add_argument("--dry-run", action="store_true", help="Export and validate the merged schema without importing it.")
    parser.add_argument("--backup-dir", type=Path, default=DEFAULT_BACKUP_DIR)
    parser.add_argument("--no-backup", action="store_true")
    args = parser.parse_args()
    args.team_id = resolve_team_id(args)
    if args.environment != "development":
        raise SystemExit("Schema import is only supported for development. Deploy schema changes to production from CloudKit Console.")

    fragment_file = args.record_type_fragment
    if not fragment_file.is_absolute():
        fragment_file = (REPO_ROOT / fragment_file).resolve()
    if not fragment_file.exists():
        raise SystemExit(f"找不到 record type 片段文件: {fragment_file}")

    current_schema = export_current_schema(args)
    if schema_contains_record_type(current_schema, RECORD_TYPE):
        print(f"{args.environment} schema already contains {RECORD_TYPE}; nothing to import.")
        return

    record_type_fragment = fragment_file.read_text(encoding="utf-8")
    schema_text = merged_schema(current_schema, record_type_fragment)
    write_schema_backups(args, current_schema, schema_text)

    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".ckdb", delete=False) as schema_file:
        schema_file.write(schema_text)
        schema_path = Path(schema_file.name)

    try:
        if not args.skip_validate:
            run(
                cktool_command(args, "validate-schema")
                + [
                    "--team-id",
                    args.team_id,
                    "--container-id",
                    args.container_id,
                    "--environment",
                    args.environment,
                    "--file",
                    str(schema_path),
                ]
            )

        if args.dry_run:
            print(f"Dry run complete. Merged schema was not imported into {args.environment}.")
        else:
            run(
                cktool_command(args, "import-schema")
                + [
                    "--team-id",
                    args.team_id,
                    "--container-id",
                    args.container_id,
                    "--environment",
                    args.environment,
                    "--file",
                    str(schema_path),
                ]
            )
    finally:
        schema_path.unlink(missing_ok=True)


if __name__ == "__main__":
    main()
