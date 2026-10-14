package com.sonicloud.voice

import android.content.Context
import com.k2fsa.sherpa.onnx.FeatureConfig
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineSenseVoiceModelConfig
import com.k2fsa.sherpa.onnx.OfflineStream
import com.k2fsa.sherpa.onnx.OfflineTts
import com.k2fsa.sherpa.onnx.OfflineTtsConfig
import com.k2fsa.sherpa.onnx.OfflineTtsKokoroModelConfig
import com.k2fsa.sherpa.onnx.OfflineTtsModelConfig
import com.k2fsa.sherpa.onnx.WaveReader
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter bridge. VoiceRuntime is the only class that needs Sherpa-ONNX JNI. */
class SoniCloudVoicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var runtime: VoiceRuntime

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.sonicloud.voice")
        runtime = NativeVoiceRuntime(binding.applicationContext)
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        runtime.close()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "capabilities" -> result.success(runtime.capabilities())
                "prepareModels" -> { runtime.prepareModels(call.argument<String>("language")); result.success(null) }
                "transcribe" -> result.success(runtime.transcribe(call.argument<String>("path") ?: error("path is required"), call.argument<String>("language") ?: "auto"))
                "synthesize" -> result.success(runtime.synthesize(call.argument<String>("text") ?: error("text is required"), call.argument<String>("language") ?: "zh", call.argument<String>("voice") ?: "default", call.argument<Double>("speed") ?: 1.0))
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("VOICE_ERROR", error.message, null)
        }
    }
}

interface VoiceRuntime {
    fun capabilities(): Map<String, Any>
    fun prepareModels(language: String?)
    fun transcribe(path: String, language: String): Map<String, Any>
    fun synthesize(text: String, language: String, voice: String, speed: Double): Map<String, Any>
    fun close()
}

private class NativeVoiceRuntime(private val context: Context) : VoiceRuntime {
    private val modelRoot = context.filesDir.resolve("voice-models")
    private var recognizer: OfflineRecognizer? = null
    private var tts: OfflineTts? = null

    override fun capabilities(): Map<String, Any> = mapOf(
        "backend" to "sherpa-onnx-1.13.8-aar",
        "asr" to mapOf("available" to asrReady(), "languages" to listOf("auto", "zh", "en", "yue", "ja", "ko")),
        "tts" to mapOf("available" to ttsReady(), "languages" to listOf("zh", "en")),
    )

    override fun prepareModels(language: String?) {
        require(asrReady() || ttsReady()) { "Voice models are not installed under ${modelRoot.path}" }
    }

    override fun transcribe(path: String, language: String): Map<String, Any> {
        val wave = WaveReader.Companion.readWave(path) ?: error("Unable to read WAV file: $path")
        require(wave.sampleRate == 16000) { "ASR requires a 16 kHz WAV file" }
        val engine = recognizer ?: createRecognizer(language).also { recognizer = it }
        val stream: OfflineStream = engine.createStream()
        stream.acceptWaveform(wave.samples, wave.sampleRate)
        engine.decode(stream)
        val decoded = engine.getResult(stream)
        stream.release()
        return mapOf(
            "text" to decoded.text,
            "language" to (decoded.lang.ifBlank { language }),
            "model" to "sensevoice-2025-09-09",
            "segments" to emptyList<Map<String, Any>>(),
        )
    }

    override fun synthesize(text: String, language: String, voice: String, speed: Double): Map<String, Any> {
        require(text.isNotBlank()) { "text must not be empty" }
        require(language == "zh" || language == "en") { "Kokoro TTS supports zh and en" }
        require(speed > 0) { "speed must be greater than zero" }
        val engine = tts ?: createTts().also { tts = it }
        val generated = engine.generate(text, 0, speed.toFloat())
        val output = context.cacheDir.resolve("tts-${text.hashCode()}-${language}.wav")
        check(generated.save(output.path)) { "Unable to save generated speech" }
        return mapOf("path" to output.path, "sampleRate" to engine.sampleRate(), "duration" to generated.samples.size.toDouble() / engine.sampleRate(), "model" to "kokoro-1.0", "voice" to voice)
    }

    override fun close() {
        recognizer?.release()
        recognizer = null
        tts?.free()
        tts = null
    }

    private fun asrDir() = modelRoot.resolve("sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09")
    private fun ttsDir() = modelRoot.resolve("kokoro-int8-multi-lang-v1_0")
    private fun asrReady() = asrDir().resolve("model.int8.onnx").isFile && asrDir().resolve("tokens.txt").isFile
    private fun ttsReady() = ttsDir().resolve("model.onnx").isFile && ttsDir().resolve("voices.bin").isFile && ttsDir().resolve("tokens.txt").isFile

    private fun createRecognizer(language: String): OfflineRecognizer {
        require(asrReady()) { "ASR model is not installed under ${asrDir().path}" }
        val sense = OfflineSenseVoiceModelConfig().apply {
            model = asrDir().resolve("model.int8.onnx").path
            this.language = language
            useInverseTextNormalization = true
        }
        val model = OfflineModelConfig().apply {
            tokens = asrDir().resolve("tokens.txt").path
            numThreads = 2
            provider = "cpu"
            senseVoice = sense
        }
        val config = OfflineRecognizerConfig().apply {
            featConfig = FeatureConfig().apply { sampleRate = 16000; featureDim = 80 }
            modelConfig = model
            decodingMethod = "greedy_search"
        }
        // Sherpa's Android API uses file paths when AssetManager is null.
        return OfflineRecognizer(null, config)
    }

    private fun createTts(): OfflineTts {
        require(ttsReady()) { "TTS model is not installed under ${ttsDir().path}" }
        val kokoro = OfflineTtsKokoroModelConfig().apply {
            model = ttsDir().resolve("model.onnx").path
            voices = ttsDir().resolve("voices.bin").path
            tokens = ttsDir().resolve("tokens.txt").path
            dataDir = ttsDir().resolve("espeak-ng-data").path
            lexicon = listOf("lexicon-us-en.txt", "lexicon-zh.txt").joinToString(",") { ttsDir().resolve(it).path }
        }
        val model = OfflineTtsModelConfig().apply { kokoro = kokoro; numThreads = 2; provider = "cpu" }
        val config = OfflineTtsConfig().apply { this.model = model; maxNumSentences = 1 }
        return OfflineTts(null, config)
    }
}
