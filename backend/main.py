import base64
import io
import os
import sys
from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np
import onnxruntime as ort
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_ROOT = Path(__file__).resolve().parent

MODEL_FILENAME_CANDIDATES = [
    "burn_model_attention_v2.onnx",
    "model.onnx",
    "best.onnx",
]


def get_current_model_version() -> str:
    env_version = os.environ.get("CURRENT_MODEL_VERSION", "").strip()
    if env_version:
        return env_version

    version_file = BACKEND_ROOT / "models" / "CURRENT_MODEL.txt"
    if version_file.exists():
        version = version_file.read_text(encoding="utf-8").strip()
        if version:
            return version
    return "v1"


def resolve_model_path() -> Path:
    model_root_override = os.environ.get("BURN_MODEL_ROOT", "").strip()
    model_path_override = os.environ.get("MODEL_PATH", "").strip()

    if model_path_override:
        candidate = Path(model_path_override).expanduser()
        if candidate.exists():
            return candidate.resolve()

    candidate_roots = []
    if model_root_override:
        candidate_roots.append(Path(model_root_override).expanduser())
    candidate_roots.extend([
        BACKEND_ROOT,
        BACKEND_ROOT / "models" / "versions" / get_current_model_version(),
        BACKEND_ROOT / "models",
        PROJECT_ROOT,
        Path.cwd(),
    ])

    seen_root_paths = set()
    ordered_roots = []
    for candidate in candidate_roots:
        try:
            resolved = candidate.resolve()
        except OSError:
            resolved = candidate
        if resolved not in seen_root_paths:
            seen_root_paths.add(resolved)
            ordered_roots.append(resolved)

    for root in ordered_roots:
        for filename in MODEL_FILENAME_CANDIDATES:
            path = root / filename
            if path.exists():
                return path.resolve()

        version_dir = root / "versions" / get_current_model_version()
        if version_dir.exists():
            for filename in MODEL_FILENAME_CANDIDATES:
                path = version_dir / filename
                if path.exists():
                    return path.resolve()

    fallback = BACKEND_ROOT / "models" / "versions" / get_current_model_version() / "burn_model_attention_v2.onnx"
    if not fallback.exists():
        fallback = BACKEND_ROOT / "burn_model_attention_v2.onnx"
    return fallback.resolve()


MODEL_PATH = resolve_model_path()
FACE_CASCADE = cv2.CascadeClassifier(
    os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml")
)
app = FastAPI(title="Burn Detection API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@lru_cache(maxsize=8)
def load_model(model_path: str):
    path = Path(model_path)
    if not path.exists():
        raise FileNotFoundError(f"Model not found: {path}")
    return ort.InferenceSession(str(path), providers=["CPUExecutionProvider"])


def encode_overlay(mask: np.ndarray) -> str:
    original = np.zeros((*mask.shape, 4), dtype=np.uint8)
    original[:, :, 0] = 255
    original[:, :, 3] = np.where(mask == 1, 115, 0).astype(np.uint8)
    output = Image.fromarray(original, mode="RGBA")
    buffer = io.BytesIO()
    output.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def protect_face(image: Image.Image) -> Image.Image:
    image_np = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
    gray = cv2.cvtColor(image_np, cv2.COLOR_BGR2GRAY)
    faces = FACE_CASCADE.detectMultiScale(gray, 1.1, 5, minSize=(40, 40))
    for x, y, width, height in faces:
        padding = int(max(width, height) * 0.2)
        x0 = max(0, x - padding)
        y0 = max(0, y - padding)
        x1 = min(image_np.shape[1], x + width + padding)
        y1 = min(image_np.shape[0], y + height + padding)
        crop = image_np[y0:y1, x0:x1]
        if crop.size:
            image_np[y0:y1, x0:x1] = cv2.GaussianBlur(crop, (0, 0), 18)
    return Image.fromarray(cv2.cvtColor(image_np, cv2.COLOR_BGR2RGB))


def encode_image(image: Image.Image) -> str:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return base64.b64encode(buffer.getvalue()).decode("ascii")


def get_model_metadata() -> dict:
    active_model = resolve_model_path()
    return {
        "version": get_current_model_version(),
        "path": str(active_model),
        "filename": active_model.name,
        "exists": active_model.exists(),
        "resolved_from_current_version_file": (BACKEND_ROOT / "models" / "CURRENT_MODEL.txt").exists(),
    }


@app.get("/health")
def health():
    metadata = get_model_metadata()
    return {"status": "ok", "model": metadata["filename"], "version": metadata["version"]}


@app.get("/model/active")
def model_active():
    return get_model_metadata()


@app.post("/predict")
async def predict(
    image: UploadFile = File(...),
    sensitivity: float = Form(0.5),
    enhance: bool = Form(False),
    blur_face: bool = Form(True),
):
    try:
        image_bytes = await image.read()
        original = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        processed = original
        if enhance:
            image_np = cv2.cvtColor(np.array(processed), cv2.COLOR_RGB2LAB)
            lab_l, lab_a, lab_b = cv2.split(image_np)
            lab_l = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(lab_l)
            processed = Image.fromarray(
                cv2.cvtColor(cv2.merge((lab_l, lab_a, lab_b)), cv2.COLOR_LAB2RGB)
            )
        if blur_face:
            processed = protect_face(processed)
        input_image = np.asarray(processed.resize((256, 256)), dtype=np.float32) / 255.0
        input_tensor = np.transpose(input_image, (2, 0, 1))[None, ...]
        active_model = resolve_model_path()
        session = load_model(str(active_model))
        output_name = session.get_outputs()[0].name
        input_name = session.get_inputs()[0].name
        logits = session.run([output_name], {input_name: input_tensor})[0]
        probabilities = 1.0 / (1.0 + np.exp(-logits))
        mask = (probabilities.squeeze() > sensitivity).astype(np.uint8)
        mask = cv2.resize(
            mask,
            (processed.width, processed.height),
            interpolation=cv2.INTER_NEAREST,
        )
        burn_pixels = int(mask.sum())
        image_pixels = int(mask.size)
        pixel_percent = burn_pixels / image_pixels * 100 if image_pixels else 0

        return {
            "maskPngBase64": encode_overlay(mask),
            "protectedImageBase64": encode_image(processed),
            "detectedRegion": "Review anatomical region",
            "burnPixelPercent": round(pixel_percent, 2),
            "tbsaEstimate": None,
            "tbsaMethod": "TBSA is not inferred from image pixels. Select anatomical regions with Rule of Nines or Lund-Browder.",
            "privacyNote": "Face blur is automatic when enabled. Mark private areas manually with the privacy brush.",
        }
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
