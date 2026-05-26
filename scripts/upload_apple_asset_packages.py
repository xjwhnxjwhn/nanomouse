#!/usr/bin/env python3
"""Upload Nanomouse downloadable assets to CloudKit Public Database.

The app reads these records before falling back to GitHub raw zips.
Requires Xcode's cktool and a saved user token:

  xcrun cktool save-token --type user --method keychain
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path


CONTAINER_ID = "iCloud.com.XiangqingZHANG.nanomouse"
RECORD_TYPE = "NanomouseAssetPackage"
ASSET_KEY = "ASSET"
REPO_ROOT = Path(__file__).resolve().parent.parent
IOS_PROJECT = REPO_ROOT / "ios" / "Hamster.xcodeproj"
IOS_SCHEME = "Hamster"


@dataclass
class AssetPackage:
    package_id: str
    file_name: str
    title: str
    published_at: str
    min_shared_support_version: str
    sha256: str
    path: Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_manifest_packages(zips_dir: Path) -> list[AssetPackage]:
    manifest_path = zips_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    packages: list[AssetPackage] = []
    for item in manifest["packages"]:
        path = zips_dir / item["fileName"]
        if not path.exists():
            raise FileNotFoundError(path)
        packages.append(
            AssetPackage(
                package_id=item["id"],
                file_name=item["fileName"],
                title=item.get("title") or item["id"],
                published_at=item.get("publishedAt") or "",
                min_shared_support_version=item.get("minSharedSupportVersion") or "",
                sha256=item.get("sha256") or sha256(path),
                path=path,
            )
        )
    return packages


def load_extra_packages(zips_dir: Path, published_at: str) -> list[AssetPackage]:
    extras: list[AssetPackage] = []
    known = {
        "zenz-v3.1-xsmall-Q5_K_M.gguf": ("azookey-zenzai-low", "AzooKey Zenzai Low"),
        "zenz-v3.1-small-Q5_K_M.gguf": ("azookey-zenzai-high", "AzooKey Zenzai High"),
        "predict_traditional.db": ("rime-predict-traditional", "Rime 繁体联想词库"),
    }
    for file_name, (package_id, title) in known.items():
        path = zips_dir / file_name
        if not path.exists():
            continue
        extras.append(
            AssetPackage(
                package_id=package_id,
                file_name=file_name,
                title=title,
                published_at=published_at,
                min_shared_support_version="",
                sha256=sha256(path),
                path=path,
            )
        )
    return extras


def cktool_base(args: argparse.Namespace) -> list[str]:
    command = [
        "xcrun",
        "cktool",
    ]
    if args.token:
        command.extend(["--token", args.token])
    return command


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


def run(command: list[str], dry_run: bool) -> None:
    print("+", " ".join(command))
    if not dry_run:
        subprocess.run(command, check=True)


def fields_json(package: AssetPackage) -> dict[str, dict[str, str]]:
    return {
        "id": {"type": "stringType", "value": package.package_id},
        "fileName": {"type": "stringType", "value": package.file_name},
        "title": {"type": "stringType", "value": package.title},
        "publishedAt": {"type": "stringType", "value": package.published_at},
        "sha256": {"type": "stringType", "value": package.sha256},
        "minSharedSupportVersion": {
            "type": "stringType",
            "value": package.min_shared_support_version,
        },
        "asset": {"type": "assetType", "value": ASSET_KEY},
    }


def delete_existing(package: AssetPackage, args: argparse.Namespace) -> None:
    command = cktool_base(args) + [
        "delete-records",
        "--container-id",
        args.container_id,
        "--environment",
        args.environment,
        "--database-type",
        "public",
        "--record-type",
        RECORD_TYPE,
        "--filters",
        f'id == "{package.package_id}"',
        "--dry-run",
        "false",
        "--yes",
    ]
    run(command, args.dry_run)


def create_record(package: AssetPackage, args: argparse.Namespace) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json", delete=False) as fields_file:
        json.dump(fields_json(package), fields_file, ensure_ascii=False)
        fields_path = Path(fields_file.name)

    command = cktool_base(args) + [
        "create-record",
        "--team-id",
        args.team_id,
        "--container-id",
        args.container_id,
        "--environment",
        args.environment,
        "--database-type",
        "public",
        "--record-type",
        RECORD_TYPE,
        "--fields-file",
        str(fields_path),
        "--asset-files",
        f"{ASSET_KEY}={package.path}",
    ]
    try:
        run(command, args.dry_run)
    finally:
        fields_path.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--team-id", help="Apple Developer Team ID. Omit to read DEVELOPMENT_TEAM from ios/Hamster.xcodeproj.")
    parser.add_argument("--container-id", default=CONTAINER_ID)
    parser.add_argument("--environment", choices=["development", "production"], default="development")
    parser.add_argument("--zips-dir", type=Path, default=Path("zips"))
    parser.add_argument("--token")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--extra-published-at",
        default="",
        help="publishedAt value for extra non-manifest assets such as zenzai weights.",
    )
    args = parser.parse_args()
    args.team_id = resolve_team_id(args)

    zips_dir = args.zips_dir
    if not zips_dir.is_absolute():
        zips_dir = (REPO_ROOT / zips_dir).resolve()
    packages = load_manifest_packages(zips_dir)
    packages.extend(load_extra_packages(zips_dir, args.extra_published_at))

    for package in packages:
        print(f"\nUploading {package.package_id} -> {package.file_name}")
        delete_existing(package, args)
        create_record(package, args)


if __name__ == "__main__":
    main()
