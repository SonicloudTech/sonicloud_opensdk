import Flutter
import Foundation

/// iOS bridge. The Objective-C++ C API adapter is selected by default; tests
/// can inject another VoiceRuntime through the initializer.
public final class SoniCloudVoicePlugin: NSObject, FlutterPlugin {
  private let runtime: VoiceRuntime

  public init(runtime: VoiceRuntime? = nil) {
    if let runtime {
      self.runtime = runtime
    } else {
      let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
      self.runtime = NativeVoiceRuntime(modelRoot: support.appendingPathComponent("VoiceModels", isDirectory: true).path)
    }
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "com.sonicloud.voice", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SoniCloudVoicePlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "capabilities": result(try runtime.capabilities())
      case "prepareModels": try runtime.prepareModels(language: args["language"] as? String); result(nil)
      case "transcribe": result(try runtime.transcribe(path: args["path"] as? String ?? "", language: args["language"] as? String ?? "auto"))
      case "synthesize": result(try runtime.synthesize(text: args["text"] as? String ?? "", language: args["language"] as? String ?? "zh", voice: args["voice"] as? String ?? "default", speed: args["speed"] as? Double ?? 1.0))
      default: result(FlutterMethodNotImplemented)
      }
    } catch { result(FlutterError(code: "VOICE_ERROR", message: error.localizedDescription, details: nil)) }
  }
}

public protocol VoiceRuntime {
  func capabilities() throws -> [String: Any]
  func prepareModels(language: String?) throws
  func transcribe(path: String, language: String) throws -> [String: Any]
  func synthesize(text: String, language: String, voice: String, speed: Double) throws -> [String: Any]
}

private final class NativeVoiceRuntime: VoiceRuntime {
  private let runtime: SoniCloudSherpaVoiceRuntime

  init(modelRoot: String) {
    runtime = SoniCloudSherpaVoiceRuntime(modelRoot: modelRoot)
  }

  func capabilities() throws -> [String: Any] { runtime.capabilities() as? [String: Any] ?? [:] }

  func prepareModels(language: String?) throws {
    var error: NSError?
    runtime.prepareModels(language: language, error: &error)
    if let error { throw error }
  }

  func transcribe(path: String, language: String) throws -> [String: Any] {
    var error: NSError?
    let result = runtime.transcribe(path: path, language: language, error: &error)
    if let error { throw error }
    return result as? [String: Any] ?? [:]
  }

  func synthesize(text: String, language: String, voice: String, speed: Double) throws -> [String: Any] {
    var error: NSError?
    let result = runtime.synthesize(text: text, language: language, voice: voice, speed: speed, error: &error)
    if let error { throw error }
    return result as? [String: Any] ?? [:]
  }
}
