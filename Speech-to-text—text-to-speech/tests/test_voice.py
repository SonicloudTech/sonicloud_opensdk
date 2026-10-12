"""Shared Voice Engine contract tests that do not require model downloads."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "python"))

from sonicloud_voice.voice import VoiceEngine


class TestVoiceEngine(unittest.TestCase):
    def test_capabilities_report_models_without_importing_runtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            model_dir = Path(tmp)
            manifest = {
                "models": {
                    "asr_sensevoice": {"directory": "asr", "languages": ["auto", "zh"]},
                    "tts_kokoro_multilingual": {"directory": "tts", "languages": ["zh", "en"]},
                }
            }
            (model_dir / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            capabilities = VoiceEngine(model_dir / "out", model_dir).capabilities()
            self.assertEqual(capabilities["backend"], "sherpa-onnx")
            self.assertEqual(capabilities["tts"]["languages"], ["zh", "en"])
            self.assertFalse(capabilities["asr"]["available"])
            self.assertFalse(capabilities["tts"]["available"])

    def test_synthesize_validates_input_before_loading_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            engine = VoiceEngine(Path(tmp))
            with self.assertRaises(ValueError):
                engine.synthesize("", "zh")
            with self.assertRaises(ValueError):
                engine.synthesize("hello", "fr")
            with self.assertRaises(ValueError):
                engine.synthesize("hello", "en", speed=0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
