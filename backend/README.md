---
title: Burn Detection API
emoji: medical_symbol
colorFrom: blue
colorTo: green
sdk: docker
app_port: 7860
---

# Burn Detection API

This service loads the model from either:

- the `BURN_MODEL_ROOT` environment variable
- the `MODEL_PATH` environment variable
- a `burn_model_attention_v2.onnx` file in the backend project, repo root, or current directory

It exposes:

- `GET /health`
- `POST /predict` with multipart field `image`

Start it from the project root with the model environment:

```powershell
$env:BURN_MODEL_ROOT = 'C:\path\to\model-folder'
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

Or with a direct file path:

```powershell
$env:MODEL_PATH = 'C:\path\to\burn_model_attention_v2.onnx'
python -m uvicorn backend.main:app --host 0.0.0.0 --port 8000
```

For local Android emulator testing, the app reaches the PC service at `http://10.0.2.2:8000`.
For a physical phone on the same network, build the app with your computer's LAN address, for example:

```powershell
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

The returned `tbsaEstimate` is a segmentation pixel estimate and must be clinically reviewed with Rule of Nines or Lund-Browder. It is not a validated anatomical TBSA measurement.

## Hugging Face Spaces

Create a new Space with **Docker** as the SDK, then upload the contents of this `backend` folder. The Space will start on port `7860` and expose `/health` and `/predict`.

After the Space is running, verify:

```text
https://YOUR-SPACE-NAME-YOUR-USERNAME.hf.space/health
```

Use that Space URL in the Flutter build:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-SPACE-NAME-YOUR-USERNAME.hf.space
```

## Render

The repository includes `render.yaml` for a Render web service. In Render, choose **New > Blueprint** and connect this repository. Render will use `backend/Dockerfile`, expose the service on its assigned `PORT`, and check `/health`.

After deployment, verify:

```text
https://YOUR-RENDER-SERVICE.onrender.com/health
```

Build Flutter with the Render URL:

```powershell
flutter build web --release --dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com
```

The repository also includes a GitHub Actions workflow for free GitHub Pages
hosting. In the repository settings, enable Pages with **GitHub Actions** as
the source and add an `API_BASE_URL` Actions secret containing the deployed
backend URL. Push to `master` to build and publish the Flutter web app at:

```text
https://YOUR-USERNAME.github.io/burncare-app/
```
