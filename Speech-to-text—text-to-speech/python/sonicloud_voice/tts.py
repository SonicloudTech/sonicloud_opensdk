"""Compatibility wrapper for the shared Voice Engine TTS capability."""
from pathlib import Path

from .voice import SynthesisResult, VoiceEngine, VoiceNotAvailable


def synthesize_file(path: Path, text: str, language: str = "zh", voice: str = "default", speed: float = 1.0) -> SynthesisResult:
    return VoiceEngine(Path(path).parent).synthesize(text, language, voice, speed)
