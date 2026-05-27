"""Organize files into forensic case directories.

This utility moves files from a source directory into a case-specific
destination while renaming them with a timestamp and SHA-256 digest.
It can be run in a dry-run mode that lists actions without modifying
the filesystem.
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class CaseEntry:
    """Represents a moved file."""

    original: Path
    destination: Path
    digest: str


DEFAULT_DEST = Path("cases")


def hash_file(path: Path) -> str:
    """Return the SHA-256 hex digest of *path*."""
    hasher = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def organize_case(
    source: Path,
    case_id: str,
    dest_base: Path = DEFAULT_DEST,
    dry_run: bool = False,
) -> list[CaseEntry]:
    """Move files from *source* into a case directory."""
    entries: list[CaseEntry] = []
    dest_dir = dest_base / case_id
    dest_dir.mkdir(parents=True, exist_ok=True)
    for file in source.iterdir():
        if not file.is_file():
            continue
        digest = hash_file(file)
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        new_name = f"{timestamp}_{digest[:8]}{file.suffix.lower()}"
        dest = dest_dir / new_name
        entries.append(CaseEntry(file, dest, digest))
        if not dry_run:
            shutil.move(str(file), dest)
    return entries


def parse_args() -> argparse.Namespace:
    """Return parsed command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("case_id", type=str)
    parser.add_argument("--dest", type=Path, default=DEFAULT_DEST)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> None:
    """Entry point for command-line execution."""
    args = parse_args()
    results = organize_case(args.source, args.case_id, args.dest, args.dry_run)
    for entry in results:
        print(f"{entry.original} -> {entry.destination} {entry.digest}")


if __name__ == "__main__":
    main()
