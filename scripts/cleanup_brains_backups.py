"""Utilities for maintaining BRAINS backups.

This script removes BRAINS backup directories older than a specified
number of days. By default, backups older than 30 days are deleted.

Usage:
    python cleanup_brains_backups.py [--path PATH] [--days DAYS] [--dry-run]
"""

from __future__ import annotations

import argparse
import datetime as dt
from pathlib import Path
import shutil


class CleanupResult:
    """Return value from :func:`cleanup_backups`."""

    def __init__(self, deleted: list[Path]):
        self.deleted = deleted

    def __iter__(self):
        return iter(self.deleted)


DEFAULT_DAYS = 30
DEFAULT_PATH = Path("storage/backup")


def cleanup_backups(
    path: Path,
    days: int,
    dry_run: bool = False,
) -> CleanupResult:
    """Delete subdirectories in *path* older than *days* days."""
    deleted: list[Path] = []

    if days <= 0:
        return CleanupResult(deleted)

    cutoff = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)
    if not path.exists():
        return CleanupResult(deleted)

    for child in path.iterdir():
        if not child.is_dir():
            continue
        mtime = dt.datetime.fromtimestamp(
            child.stat().st_mtime,
            dt.timezone.utc,
        )
        if mtime < cutoff:
            deleted.append(child)
            if not dry_run:
                shutil.rmtree(child, ignore_errors=True)

    return CleanupResult(deleted)


def parse_args() -> argparse.Namespace:
    """Return parsed command-line arguments."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", type=Path, default=DEFAULT_PATH)
    parser.add_argument("--days", type=int, default=DEFAULT_DAYS)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> None:
    """Entry point for command-line execution."""
    args = parse_args()
    result = cleanup_backups(args.path, args.days, dry_run=args.dry_run)
    for item in result:
        print(item)


if __name__ == "__main__":
    main()
