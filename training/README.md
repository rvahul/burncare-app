# Safe retraining pipeline for BurnCare

This folder contains a safe batch-retraining workflow for the burn-detection model.

## Principle

This project does not perform live online training from raw hospital uploads. Instead:

1. New images are collected and stored securely.
2. Images are reviewed and labeled by a clinician or expert.
3. Only reviewed data is added to the training dataset.
4. A batch retraining job is triggered when enough approved data is available.
5. The new model is validated before being promoted.
6. The production backend only uses the newest approved model version.

## Recommended data flow

- `training/data/unreviewed/` stores new uploaded images
- `training/data/reviewed/` stores approved images and masks
- `training/scripts/train_model.py` runs the retraining job
- `training/scripts/validate_model.py` checks metrics and safety
- `training/scripts/export_onnx.py` exports a versioned ONNX model

## Safety rules

- No automatic retraining on every image
- No direct use of unreviewed hospital data for training
- Model updates should require human approval
- Keep models versioned and reversible

## Production deployment

- Active model lives in `backend/models/current/`
- Approved model versions live in `backend/models/versions/`
- The FastAPI backend loads the current approved model only

## Typical workflow

1. Collect a batch of reviewed images
2. Run `train_model.py`
3. Validate the new model
4. Export ONNX to a versioned folder
5. Promote the model manually
6. Update the backend model reference
