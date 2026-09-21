from __future__ import annotations

import json
from pathlib import Path

DATA_ROOT = Path(__file__).resolve().parents[1]
UNREVIEWED = DATA_ROOT / "data" / "unreviewed"
REVIEWED = DATA_ROOT / "data" / "reviewed"


def scan_unreviewed() -> list[Path]:
    if not UNREVIEWED.exists():
        return []
    return sorted(p for p in UNREVIEWED.rglob("*") if p.is_file())


def scan_reviewed() -> list[Path]:
    if not REVIEWED.exists():
        return []
    return sorted(p for p in REVIEWED.rglob("*") if p.is_file())


def build_dataset_index() -> dict:
    reviewed = scan_reviewed()
    unreviewed = scan_unreviewed()
    return {
        "reviewed_count": len(reviewed),
        "unreviewed_count": len(unreviewed),
        "reviewed_files": [str(p.relative_to(DATA_ROOT)) for p in reviewed],
        "unreviewed_files": [str(p.relative_to(DATA_ROOT)) for p in unreviewed],
    }


if __name__ == "__main__":
    index = build_dataset_index()
    print(json.dumps(index, indent=2))
