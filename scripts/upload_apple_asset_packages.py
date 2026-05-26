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
KNOWN_EXTRA_PACKAGES = {
    "zenz-v3.1-xsmall-Q5_K_M.gguf": ("azookey-zenzai-low", "AzooKey Zenzai Low"),
    "zenz-v3.1-small-Q5_K_M.gguf": ("azookey-zenzai-high", "AzooKey Zenzai High"),
    "predict_traditional.db": ("rime-predict-traditional", "Rime 繁体联想词库"),
}


@dataclass
class AssetPackage:
    package_id: str
    file_name: str
    title: str
    published_at: str
    min_shared_support_version: str
    sha256: str
    path: Path


ZERO_GIT_SHA = "0000000000000000000000000000000000000000"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_manifest_identity(package: AssetPackage) -> tuple[str, str, str, str, str, str]:
    return (
        package.package_id,
        package.file_name,
        package.title,
        package.published_at,
        package.min_shared_support_version,
        package.sha256,
    )


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
    for file_name, (package_id, title) in KNOWN_EXTRA_PACKAGES.items():
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


def git_output(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=REPO_ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def git_ref_exists(ref: str) -> bool:
    if not ref or ref == ZERO_GIT_SHA:
        return False
    return subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        cwd=REPO_ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    ).returncode == 0


def changed_paths_between(base: str, head: str) -> set[str] | None:
    if not git_ref_exists(base) or not git_ref_exists(head):
        return None
    output = git_output(["diff", "--name-only", base, head, "--", "zips"])
    return {line.strip() for line in output.splitlines() if line.strip()}


def manifest_packages_at_ref(ref: str, zips_dir: Path) -> dict[str, AssetPackage]:
    try:
        raw = git_output(["show", f"{ref}:zips/manifest.json"])
    except subprocess.CalledProcessError:
        return {}

    manifest = json.loads(raw)
    packages: dict[str, AssetPackage] = {}
    for item in manifest["packages"]:
        path = zips_dir / item["fileName"]
        packages[item["id"]] = AssetPackage(
            package_id=item["id"],
            file_name=item["fileName"],
            title=item.get("title") or item["id"],
            published_at=item.get("publishedAt") or "",
            min_shared_support_version=item.get("minSharedSupportVersion") or "",
            sha256=item.get("sha256") or "",
            path=path,
        )
    return packages


def filter_changed_packages(
    packages: list[AssetPackage],
    zips_dir: Path,
    base: str | None,
    head: str | None,
) -> list[AssetPackage]:
    if not base or not head:
        return packages

    changed_paths = changed_paths_between(base, head)
    if changed_paths is None:
        print("Unable to resolve git range; uploading all packages.")
        return packages

    relative_zips_dir = zips_dir.relative_to(REPO_ROOT) if zips_dir.is_relative_to(REPO_ROOT) else Path("zips")
    changed_file_names = {
        Path(path).name
        for path in changed_paths
        if Path(path).parent == relative_zips_dir
    }
    manifest_changed = Path(f"{relative_zips_dir}/manifest.json").as_posix() in changed_paths
    previous_manifest = manifest_packages_at_ref(base, zips_dir)
    selected: list[AssetPackage] = []

    for package in packages:
        file_changed = package.file_name in changed_file_names
        previous = previous_manifest.get(package.package_id)
        metadata_changed = (
            manifest_changed
            and previous is not None
            and package_manifest_identity(package) != package_manifest_identity(previous)
        )
        added_to_manifest = (
            manifest_changed
            and previous is None
            and package.file_name not in KNOWN_EXTRA_PACKAGES
        )
        if file_changed or metadata_changed or added_to_manifest:
            selected.append(package)

    return selected


def cktool_command(args: argparse.Namespace, subcommand: str) -> list[str]:
    command = [
        "xcrun",
        "cktool",
        subcommand,
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


def run(command: list[str], dry_run: bool, allow_not_found: bool = False) -> None:
    redacted = command.copy()
    for index, item in enumerate(redacted[:-1]):
        if item == "--token":
            redacted[index + 1] = "***"
    print("+", " ".join(redacted))
    if dry_run:
        return

    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    if result.returncode == 0:
        return

    output = f"{result.stdout}\n{result.stderr}"
    if allow_not_found and "not-found" in output:
        print("No existing CloudKit record found; continuing.")
        return

    raise subprocess.CalledProcessError(result.returncode, command, result.stdout, result.stderr)


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
    command = cktool_command(args, "delete-records") + [
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
    run(command, args.dry_run, allow_not_found=True)


def create_record(package: AssetPackage, args: argparse.Namespace) -> None:
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".json", delete=False) as fields_file:
        json.dump(fields_json(package), fields_file, ensure_ascii=False)
        fields_path = Path(fields_file.name)

    command = cktool_command(args, "create-record") + [
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
    parser.add_argument("--git-base", help="Only upload packages changed after this commit.")
    parser.add_argument("--git-head", help="Only upload packages changed up to this commit.")
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
    packages = filter_changed_packages(packages, zips_dir, args.git_base, args.git_head)

    if not packages:
        print("No changed asset packages to upload.")
        return

    for package in packages:
        print(f"\nUploading {package.package_id} -> {package.file_name}")
        delete_existing(package, args)
        create_record(package, args)


if __name__ == "__main__":
    main()
