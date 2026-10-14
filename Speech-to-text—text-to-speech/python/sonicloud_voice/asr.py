"""Convenience API for isolated offline ASR use."""
import asyncio
from pathlib import Path

from .voice import TranscriptResult, VoiceEngine


def transcribe_file_sync(
    path: Path, language: str = "auto", model_dir: Path | None = None
) -> TranscriptResult:
    return VoiceEngine(Path(path).parent, model_dir=model_dir).transcribe_file(
        Path(path), language
    )


async def transcribe_file(
    path: Path, language: str = "auto", model_dir: Path | None = None
) -> TranscriptResult:
    loop = asyncio.get_running_loop()
    return await loop.run_in_executor(
        None, transcribe_file_sync, Path(path), language, model_dir
    )
