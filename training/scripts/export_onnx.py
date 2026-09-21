from __future__ import annotations

import json
from pathlib import Path

EXPORT_ROOT = Path(__file__).resolve().parents[1]
MODEL_OUTPUT = EXPORT_ROOT / "artifacts" / "model_versions"


def export_version(version_name: str = "v1") -> dict:
    MODEL_OUTPUT.mkdir(parents=True, exist_ok=True)
    version_dir = MODEL_OUTPUT / version_name
    version_dir.mkdir(parents=True, exist_ok=True)

    model_path = version_dir / "burn_model_attention_v2.onnx"
    model_path.write_bytes(b"placeholder-onnx-model")

    metadata = {
        "status": "exported",
        "version": version_name,
        "path": str(model_path),
        "approved": False,
    }
    (version_dir / "metadata.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")
    return metadata


if __name__ == "__main__":
    print(json.dumps(export_version(), indent=2))
