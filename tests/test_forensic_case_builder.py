import importlib.util
from pathlib import Path
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "forensic_case_builder",
    ROOT / "scripts" / "forensic_case_builder.py",
)
module = importlib.util.module_from_spec(SPEC)

sys.modules[SPEC.name] = module
SPEC.loader.exec_module(module)
hash_file = module.hash_file
organize_case = module.organize_case


def test_hash_file(tmp_path: Path) -> None:
    data = b"example"
    file = tmp_path / "file.txt"
    file.write_bytes(data)
    assert hash_file(file) == hashlib.sha256(data).hexdigest()


def test_organize_case(tmp_path: Path) -> None:
    source = tmp_path / "src"
    source.mkdir()
    file = source / "doc.txt"
    file.write_text("content")
    dest = tmp_path / "cases"
    results = organize_case(source, "CASE1", dest, dry_run=True)
    assert len(results) == 1
    entry = results[0]
    assert entry.original == file
    assert entry.destination.parent == dest / "CASE1"
    assert entry.digest == hashlib.sha256(b"content").hexdigest()
    assert file.exists()
