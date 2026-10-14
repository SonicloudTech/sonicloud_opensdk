# Voice models

This directory contains the versioned model manifest used by the SoniCloud Voice Engine. Model weights are distributed as verified release assets instead of regular Git blobs.

From this directory, install the voice dependencies and fetch both models:

```bash
pip install -r ../requirements-python.txt
python scripts/fetch_voice_models.py --all
```

The default bundle contains:

- Sherpa-ONNX SenseVoice INT8 for Chinese, English, Cantonese, Japanese, and Korean ASR.
- Sherpa-ONNX Kokoro multilingual INT8 for Chinese and English TTS.

Every archive is checked against the SHA-256 value in `manifest.json`. The model archives are third-party assets; review their upstream licenses before redistribution. To use a separately packaged model, set `SONICLOUD_VOICE_MODEL_DIR` to the extracted model root.
