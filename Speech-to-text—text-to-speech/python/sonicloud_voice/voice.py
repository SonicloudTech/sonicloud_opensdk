"""Shared offline ASR/TTS capability for the recorder project.

The module keeps the application-facing contract independent from the model
runtime. Sherpa-ONNX is optional at import time so BLE and file workflows stay
usable when voice models are not installed.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


LANGUAGES = ("auto", "zh", "en", "yue", "ja", "ko")


class VoiceNotAvailable(RuntimeError):
    """The voice runtime or its model bundle is unavailable."""


@dataclass(frozen=True)
class TranscriptSegment:
    start: float
    end: float
    text: str


@dataclass(frozen=True)
class TranscriptResult:
    text: str
    language: str
    model: str
    segments: tuple[TranscriptSegment, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class SynthesisResult:
    path: Path
    sample_rate: int
    duration: float
    model: str
    voice: str


class VoiceEngine:
    """A process-local model manager for offline ASR and TTS."""

    def __init__(self, output_dir: Path, model_dir: Path | None = None) -> None:
        self.output_dir = Path(output_dir)
        self.model_dir = Path(
            model_dir
            or os.getenv(
                "SONICLOUD_VOICE_MODEL_DIR",
                Path(__file__).resolve().parents[2] / "models",
            )
        )
        manifest_path = self.model_dir / "manifest.json"
        self.manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"models": {}}
        self._asr = {}
        self._tts = None

    def _spec(self, name: str) -> dict[str, Any]:
        return self.manifest.get("models", {}).get(name, {})

    def _model_path(self, name: str, key: str) -> Path:
        spec = self._spec(name)
        directory = self.model_dir / spec.get("directory", "")
        value = spec.get(key)
        if not value:
            raise VoiceNotAvailable(f"Model manifest is missing {name}.{key}")
        path = directory / value
        if not path.exists():
            raise VoiceNotAvailable(
                f"Voice model is not installed: {path}. "
                "Run scripts/fetch_voice_models.py --all."
            )
        return path

    def asr_ready(self) -> bool:
        try:
            self._model_path("asr_sensevoice", "model_file")
            self._model_path("asr_sensevoice", "tokens_file")
            import sherpa_onnx  # noqa: F401
            import soundfile  # noqa: F401
            return True
        except (ImportError, VoiceNotAvailable):
            return False

    def tts_ready(self) -> bool:
        try:
            for key in ("model_file", "tokens_file", "voices_file"):
                self._model_path("tts_kokoro_multilingual", key)
            import sherpa_onnx  # noqa: F401
            import soundfile  # noqa: F401
            return True
        except (ImportError, VoiceNotAvailable):
            return False

    def capabilities(self) -> dict[str, Any]:
        return {
            "backend": "sherpa-onnx",
            "asr": {
                "available": self.asr_ready(),
                "languages": list(LANGUAGES),
                "model": self._spec("asr_sensevoice").get("directory", ""),
            },
            "tts": {
                "available": self.tts_ready(),
                "languages": self._spec("tts_kokoro_multilingual").get("languages", []),
                "voices": ["default"],
                "model": self._spec("tts_kokoro_multilingual").get("directory", ""),
            },
        }

    def _load_asr(self, language: str):
        if language not in LANGUAGES:
            raise ValueError(f"language must be one of: {', '.join(LANGUAGES)}")
        if language in self._asr:
            return self._asr[language]
        try:
            import sherpa_onnx
        except ImportError as exc:
            raise VoiceNotAvailable(
                "sherpa-onnx is not installed; run pip install -r requirements-python.txt"
            ) from exc
        model = self._model_path("asr_sensevoice", "model_file")
        tokens = self._model_path("asr_sensevoice", "tokens_file")
        recognizer = sherpa_onnx.OfflineRecognizer.from_sense_voice(
            model=str(model),
            tokens=str(tokens),
            language=language,
            use_itn=True,
            num_threads=min(4, os.cpu_count() or 1),
            provider="cpu",
        )
        self._asr[language] = recognizer
        return recognizer

    def transcribe_file(self, path: Path, language: str = "auto") -> TranscriptResult:
        try:
            import soundfile as sf
        except ImportError as exc:
            raise VoiceNotAvailable(
                "soundfile is not installed; run pip install -r requirements-python.txt"
            ) from exc
        audio, sample_rate = sf.read(str(path), dtype="float32", always_2d=True)
        if sample_rate != 16000:
            raise ValueError(f"expected a 16 kHz WAV file, got {sample_rate} Hz")
        recognizer = self._load_asr(language)
        samples = audio[:, 0]
        # Keep long recordings bounded while preserving a stable segment contract.
        chunk_size = sample_rate * 30
        segments = []
        for offset in range(0, len(samples), chunk_size):
            chunk = samples[offset:offset + chunk_size]
            if len(chunk) == 0:
                continue
            stream = recognizer.create_stream()
            stream.accept_waveform(sample_rate, chunk)
            recognizer.decode_stream(stream)
            text = stream.result.text.strip()
            if text:
                start = offset / sample_rate
                end = (offset + len(chunk)) / sample_rate
                segments.append(TranscriptSegment(start, end, text))
        return TranscriptResult(
            text=" ".join(segment.text for segment in segments),
            language=language,
            model=self._spec("asr_sensevoice").get("directory", ""),
            segments=tuple(segments),
        )

    def _load_tts(self):
        if self._tts is not None:
            return self._tts
        try:
            import sherpa_onnx
        except ImportError as exc:
            raise VoiceNotAvailable(
                "sherpa-onnx is not installed; run pip install -r requirements-python.txt"
            ) from exc
        spec = self._spec("tts_kokoro_multilingual")
        model = self._model_path("tts_kokoro_multilingual", "model_file")
        voices = self._model_path("tts_kokoro_multilingual", "voices_file")
        tokens = self._model_path("tts_kokoro_multilingual", "tokens_file")
        data_dir = self._model_path("tts_kokoro_multilingual", "data_dir")
        lexicon = ",".join(str(self.model_dir / spec["directory"] / value) for value in spec.get("lexicon_files", []))
        config = sherpa_onnx.OfflineTtsConfig(
            model=sherpa_onnx.OfflineTtsModelConfig(
                kokoro=sherpa_onnx.OfflineTtsKokoroModelConfig(
                    model=str(model), voices=str(voices), tokens=str(tokens),
                    data_dir=str(data_dir), lexicon=lexicon,
                ),
                provider="cpu", num_threads=min(4, os.cpu_count() or 1),
            ),
            max_num_sentences=1,
        )
        if not config.validate():
            raise VoiceNotAvailable("Kokoro TTS model configuration is invalid")
        self._tts = sherpa_onnx.OfflineTts(config)
        return self._tts

    def synthesize(self, text: str, language: str = "zh", voice: str = "default", speed: float = 1.0) -> SynthesisResult:
        if not text.strip():
            raise ValueError("text must not be empty")
        if language not in ("zh", "en"):
            raise ValueError("Kokoro TTS currently supports zh and en")
        if voice != "default":
            raise ValueError("only the default Kokoro voice is currently exposed")
        if not math.isfinite(speed) or speed <= 0:
            raise ValueError("speed must be greater than zero")
        tts = self._load_tts()
        import soundfile as sf
        generation = __import__("sherpa_onnx").GenerationConfig()
        generation.sid = 0
        generation.speed = speed
        audio = tts.generate(text, generation)
        if len(audio.samples) == 0:
            raise VoiceNotAvailable("TTS generated no audio")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        key = hashlib.sha256(f"{language}|{voice}|{speed}|{text}".encode()).hexdigest()[:16]
        path = self.output_dir / f"tts_{key}.wav"
        sf.write(str(path), audio.samples, samplerate=audio.sample_rate, subtype="PCM_16")
        return SynthesisResult(path, audio.sample_rate, len(audio.samples) / audio.sample_rate,
                               self._spec("tts_kokoro_multilingual").get("directory", ""), voice)
