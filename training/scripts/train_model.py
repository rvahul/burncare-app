from __future__ import annotations

import json
from pathlib import Path

TRAINING_ROOT = Path(__file__).resolve().parents[1]
REVIEWED_DATA = TRAINING_ROOT / "data" / "reviewed"
OUTPUT_ROOT = TRAINING_ROOT / "artifacts"


def check_training_ready(min_images: int = 100) -> dict:
    reviewed_files = []
    if REVIEWED_DATA.exists():
        reviewed_files = sorted(
            p for p in REVIEWED_DATA.rglob("*") if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg"}
        )

    return {
        "ready": len(reviewed_files) >= min_images,
        "reviewed_images": len(reviewed_files),
        "minimum_required": min_images,
        "dataset_dir": str(REVIEWED_DATA),
    }


def train_batch() -> dict:
    status = check_training_ready()
    if not status["ready"]:
        return {
            "status": "skipped",
            "reason": "Not enough reviewed images to retrain safely.",
            **status,
        }

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    job_dir = OUTPUT_ROOT / "latest_training_run"
    job_dir.mkdir(parents=True, exist_ok=True)

    metadata = {
        "status": "training_started",
        "dataset_dir": str(REVIEWED_DATA),
        "job_dir": str(job_dir),
        "reviewed_images": status["reviewed_images"],
        "minimum_required": status["minimum_required"],
    }

    (job_dir / "training_metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")

    return {
        "status": "training_started",
        "job_dir": str(job_dir),
        "reviewed_images": status["reviewed_images"],
    }


if __name__ == "__main__":
    print(json.dumps(train_batch(), indent=2))
