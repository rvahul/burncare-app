from pathlib import Path
import os
import sys

import torch

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = Path(__file__).resolve().parent

model_root_override = os.environ.get("BURN_MODEL_ROOT", "").strip()
model_path_override = os.environ.get("MODEL_PATH", "").strip()
search_roots = []
if model_root_override:
    search_roots.append(Path(model_root_override).expanduser())
if model_path_override:
    search_roots.append(Path(model_path_override).expanduser().parent)
search_roots.extend([BACKEND_ROOT, PROJECT_ROOT, Path.cwd()])
seen_roots = set()
ordered_roots = []
for root in search_roots:
    resolved = root.resolve() if hasattr(root, "resolve") else root
    if resolved not in seen_roots:
        seen_roots.add(resolved)
        ordered_roots.append(resolved)

for root in ordered_roots:
    if (root / "attention_unet.py").exists():
        sys.path.insert(0, str(root))

try:
    from attention_unet import AttentionUNet
except ImportError:
    for root in ordered_roots:
        sys.path.insert(0, str(root))
    from attention_unet import AttentionUNet

MODEL_ROOT = next(
    (root for root in ordered_roots if (root / "burn_model_attention_v2.pth").exists()),
    BACKEND_ROOT,
)
OUTPUT_PATH = Path(__file__).resolve().parent / "burn_model_attention_v2.onnx"


def main() -> None:
    checkpoint_path = Path(model_path_override).expanduser() if model_path_override else (MODEL_ROOT / "burn_model_attention_v2.pth")
    model = AttentionUNet().to("cpu")
    state_dict = torch.load(checkpoint_path, map_location="cpu")
    model.load_state_dict(state_dict)
    model.eval()

    sample = torch.zeros(1, 3, 256, 256, dtype=torch.float32)
    with torch.no_grad():
        expected = model(sample)

    torch.onnx.export(
        model,
        sample,
        OUTPUT_PATH,
        input_names=["image"],
        output_names=["logits"],
        opset_version=17,
        dynamo=False,
        do_constant_folding=True,
    )

    print(f"exported={OUTPUT_PATH}")
    print(f"input_shape={tuple(sample.shape)}")
    print(f"output_shape={tuple(expected.shape)}")
    print(f"output_bytes={OUTPUT_PATH.stat().st_size}")


if __name__ == "__main__":
    main()
