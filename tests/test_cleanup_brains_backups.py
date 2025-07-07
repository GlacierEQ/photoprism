import os
import importlib.util
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "cleanup_brains_backups",
    ROOT / "scripts" / "cleanup_brains_backups.py",
)
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)
cleanup_backups = module.cleanup_backups


def test_cleanup_backups(tmp_path: Path) -> None:
    """Verify that only outdated backups are selected for deletion."""
    old_dir = tmp_path / "old"
    new_dir = tmp_path / "new"
    old_dir.mkdir()
    new_dir.mkdir()

    old_time = time.time() - 35 * 24 * 60 * 60
    os.utime(old_dir, times=(old_time, old_time))

    result = cleanup_backups(tmp_path, days=30, dry_run=True)
    assert old_dir in result.deleted
    assert new_dir not in result.deleted
