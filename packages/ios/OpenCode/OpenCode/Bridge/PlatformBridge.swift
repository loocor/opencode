import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import WebKit

@MainActor
final class PlatformBridge: NSObject, AVSpeechSynthesizerDelegate {
  weak var webView: WKWebView?
  var onEvent: ((String, Any?) -> Void)?

  private let haptics = HapticBridge()
  private let push = PushBridge.shared
  private let config = ServerConfig()
  private let networkScan = NetworkScanBridge()
  private let speech = AVSpeechSynthesizer()
  private var activeObserver: NSObjectProtocol?
  private var backgroundObserver: NSObjectProtocol?
  private var audioObserver: NSObjectProtocol?
  private var speechPartID: String?
  private var speechText: String?
  private var speechActive = false
  private var speechPaused = false

  override init() {
    super.init()
    speech.delegate = self
    configureRemoteCommands()
    activeObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.onEvent?("appLifecycle", ["state": "active"])
      }
      Task { @MainActor in
        _ = await self?.push.refresh(emit: true)
      }
    }

    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.onEvent?("appLifecycle", ["state": "background"])
      }
    }

    audioObserver = NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: nil,
      queue: .main
    ) { [weak self] note in
      MainActor.assumeIsolated {
        self?.handleInterruption(note.userInfo)
      }
    }

    push.onEvent = { [weak self] type, payload in
      self?.onEvent?(type, payload)
    }
  }

  deinit {
    if let activeObserver {
      NotificationCenter.default.removeObserver(activeObserver)
    }
    if let backgroundObserver {
      NotificationCenter.default.removeObserver(backgroundObserver)
    }
    if let audioObserver {
      NotificationCenter.default.removeObserver(audioObserver)
    }
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.removeTarget(nil)
    center.pauseCommand.removeTarget(nil)
    center.stopCommand.removeTarget(nil)
  }

  func webContentDidLoad() {}

  // swiftlint:disable cyclomatic_complexity function_body_length
  func handle(id: String, method: String, params: [String: Any], reply: @escaping @MainActor (Any?, String?) -> Void) {
    switch method {
    case "openLink":
      if let url = params["url"] as? String, let target = URL(string: url) {
        UIApplication.shared.open(target, options: [:], completionHandler: nil)
      }
      reply(nil, nil)
    case "notify":
      let opts = params["opts"] as? [String: Any]
      let kind = opts?["kind"] as? String
      let generic = opts?["generic"] as? Bool ?? true
      Task { @MainActor in
        _ = await push.notify(
          title: params["title"] as? String,
          body: params["description"] as? String,
          href: params["href"] as? String,
          kind: kind,
          generic: generic,
        )
        reply(nil, nil)
      }
    case "haptic":
      if let style = params["style"] as? String {
        haptics.impact(style: style)
      }
      reply(nil, nil)
    case "getPushState":
      Task { @MainActor in
        let result = await push.refresh()
        reply(result, nil)
      }
    case "requestPushPermission":
      Task { @MainActor in
        let result = await push.request()
        reply(result, nil)
      }
    case "setNotificationBadge":
      push.setBadge((params["count"] as? NSNumber)?.intValue ?? 0)
      reply(nil, nil)
    case "beginPushPairing":
      Task { @MainActor in
        do {
          let result = try await push.beginPair(version: params["version"] as? String)
          reply(result, nil)
        } catch {
          reply(nil, error.localizedDescription)
        }
      }
    case "getPushPairing":
      Task { @MainActor in
        do {
          let result = try await push.getPair()
          reply(result, nil)
        } catch {
          reply(nil, error.localizedDescription)
        }
      }
    case "openSystemSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
      reply(nil, nil)
    case "testPush":
      Task { @MainActor in
        do {
          let result = try await push.test(href: params["href"] as? String)
          reply(result, nil)
        } catch {
          reply(nil, error.localizedDescription)
        }
      }
    case "setPushPreferences":
      Task { @MainActor in
        do {
          try await push.setPrefs(
            complete: params["complete"] as? Bool ?? true,
            approval: params["approval"] as? Bool ?? true,
            question: params["question"] as? Bool ?? true,
            error: params["error"] as? Bool ?? true,
          )
          reply(nil, nil)
        } catch {
          reply(nil, error.localizedDescription)
        }
      }
    case "setPushRelayURL":
      push.setRelayURL(params["url"] as? String)
      reply(nil, nil)
    case "setPushCredentials":
      Task { @MainActor in
        let result = await push.setCredentials(
          channel: params["channel"] as? String,
          device: params["device"] as? String,
          secret: params["secret"] as? String,
        )
        reply(result, nil)
      }
    case "clearPushPairing":
      Task { @MainActor in
        do {
          let result = try await push.clearPairing()
          reply(result, nil)
        } catch {
          reply(nil, error.localizedDescription)
        }
      }
    case "consumePushOpen":
      reply(push.consume(), nil)
    case "share":
      reply(share(params: params), nil)
    case "speak":
      speak(params: params)
      reply(nil, nil)
    case "stopSpeaking":
      stopSpeaking()
      reply(nil, nil)
    case "pauseSpeaking":
      pauseSpeaking()
      reply(nil, nil)
    case "resumeSpeaking":
      resumeSpeaking()
      reply(nil, nil)
    case "getDefaultServerUrl":
      reply(config.getDefaultServerUrl(), nil)
    case "setDefaultServerUrl":
      config.setDefaultServerUrl(params["url"] as? String)
      reply(nil, nil)
    case "storageGet":
      reply(config.storageGet(name: params["name"] as? String, key: params["key"] as? String), nil)
    case "storageSet":
      config.storageSet(
        name: params["name"] as? String,
        key: params["key"] as? String,
        value: params["value"] as? String,
      )
      reply(nil, nil)
    case "storageRemove":
      config.storageRemove(name: params["name"] as? String, key: params["key"] as? String)
      reply(nil, nil)
    case "storageClear":
      config.storageClear(name: params["name"] as? String)
      reply(nil, nil)
    case "storageKey":
      let name = params["name"] as? String
      let index = (params["index"] as? NSNumber)?.intValue
      reply(config.storageKey(name: name, index: index), nil)
    case "storageLength":
      reply(config.storageLength(name: params["name"] as? String), nil)
    case "checkHealth":
      let urlString = params["url"] as? String ?? ""
      Self.nativeHealthCheck(urlString: urlString) { healthy in
        Task { @MainActor in
          reply(["healthy": healthy], nil)
        }
      }
    case "scanNetwork":
      networkScan.cancel()
      networkScan.onFound = { [weak self] result in
        self?.onEvent?("scanResult", result)
      }
      networkScan.onComplete = { [weak self] in
        self?.onEvent?("scanComplete", nil)
      }
      networkScan.scan()
      reply(nil, nil)
    case "cancelScan":
      networkScan.cancel()
      reply(nil, nil)
    case "reload":
      if let webView, let url = URL(string: "tauri://localhost/") {
        webView.load(URLRequest(url: url))
      }
      reply(nil, nil)
    case "setShellBackground":
      if let color = params["color"] as? String {
        ShellBackground.apply(cssColor: color, webView: webView)
      }
      reply(nil, nil)
    default:
      reply(nil, "Unknown method")
    }
  }

  // swiftlint:enable cyclomatic_complexity function_body_length

  private static func nativeHealthCheck(urlString: String, completion: @escaping @Sendable (Bool) -> Void) {
    guard !urlString.isEmpty,
          let url = URL(string: "\(urlString)/global/health") else {
      completion(false)
      return
    }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 5
    URLSession.shared.dataTask(with: request) { _, response, _ in
      let http = response as? HTTPURLResponse
      let healthy = http?.statusCode == 200
      DispatchQueue.main.async { completion(healthy) }
    }.resume()
  }

  private func share(params: [String: Any]) -> Bool {
    let text = params["text"] as? String
    let url = params["url"] as? String
    var items = [Any]()
    if let text { items.append(text) }
    if let url, let value = URL(string: url) { items.append(value) }
    if items.isEmpty { return false }

    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
       let window = scene.windows.first,
       let root = window.rootViewController {
      if let popover = controller.popoverPresentationController {
        popover.sourceView = root.view
        popover.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 1, height: 1)
        popover.permittedArrowDirections = []
      }
      root.present(controller, animated: true)
    }

    return true
  }

  private func setAudio(active: Bool) {
    do {
      let session = AVAudioSession.sharedInstance()
      if active {
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        UIApplication.shared.beginReceivingRemoteControlEvents()
        return
      }
      try session.setActive(false, options: .notifyOthersOnDeactivation)
      UIApplication.shared.endReceivingRemoteControlEvents()
    } catch {
      print("[OpenCode] Audio session activation failed: \(error.localizedDescription)")
    }
  }

  private func truncate(_ text: String, limit: Int = 48) -> String {
    text.count > limit ? String(text.prefix(limit)) : text
  }

  private func configureRemoteCommands() {
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.stopCommand.isEnabled = true
    center.playCommand.removeTarget(nil)
    center.pauseCommand.removeTarget(nil)
    center.stopCommand.removeTarget(nil)
    center.playCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      Task { @MainActor in
        self.resumeSpeaking()
      }
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      Task { @MainActor in
        self.pauseSpeaking()
      }
      return .success
    }
    center.stopCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      Task { @MainActor in
        self.stopSpeaking()
      }
      return .success
    }
  }

  private func nowPlaying(_ text: String? = nil) {
    guard speechActive else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }

    let value = text ?? speechText
    let title = value?
      .split(separator: "\n")
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let heading = (title?.isEmpty == false ? title : nil) ?? "OpenCode Read Aloud"
    let preview = value?
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: truncate(heading),
      MPMediaItemPropertyArtist: "Assistant",
      MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
      MPNowPlayingInfoPropertyPlaybackRate: speechPaused ? 0 : 1,
    ]
    if let preview, !preview.isEmpty {
      info[MPMediaItemPropertyAlbumTitle] = truncate(preview)
    }
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func handleInterruption(_ info: [AnyHashable: Any]?) {
    guard let value = info?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
          let type = AVAudioSession.InterruptionType(rawValue: value.uintValue) else { return }
    if type == .began {
      emitSpeech()
      return
    }
    guard let value = info?[AVAudioSessionInterruptionOptionKey] as? NSNumber else { return }
    let options = AVAudioSession.InterruptionOptions(rawValue: value.uintValue)
    if options.contains(.shouldResume), speechActive, !speechPaused {
      resumeSpeaking()
      return
    }
    emitSpeech()
  }

  private func emitSpeech() {
    var state: [String: Any] = [
      "speaking": speechActive,
      "paused": speechPaused,
    ]
    if speechActive, let speechPartID {
      state["partID"] = speechPartID
    }
    nowPlaying()
    onEvent?("speechState", state)
  }

  private func hasHan(_ text: String) -> Bool {
    text.unicodeScalars.contains(where: { 0x4E00...0x9FFF ~= $0.value || 0x3400...0x4DBF ~= $0.value })
  }

  private func voice(_ language: String) -> AVSpeechSynthesisVoice? {
    if let voice = AVSpeechSynthesisVoice(language: language) {
      return voice
    }
    return Locale.preferredLanguages
      .compactMap { AVSpeechSynthesisVoice(language: $0) }
      .first
  }

  private func voiceForText(_ text: String) -> AVSpeechSynthesisVoice? {
    if hasHan(text) {
      return voice("zh-CN") ?? voice("zh-Hans") ?? voice("zh-TW")
    }
    return Locale.preferredLanguages
      .first(where: { !$0.hasPrefix("zh") })
      .flatMap { voice($0) } ?? voice("en-US")
  }

  private func speak(params: [String: Any]) {
    let text = (params["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if text.isEmpty {
      stopSpeaking()
      return
    }

    setAudio(active: true)
    speech.stopSpeaking(at: .immediate)
    speechPartID = params["partID"] as? String
    speechText = text
    speechActive = true
    speechPaused = false

    let utterance = AVSpeechUtterance(string: text)
    utterance.rate = 0.5
    utterance.pitchMultiplier = 1
    utterance.volume = 1
    utterance.voice = voiceForText(text)
    speech.speak(utterance)
    nowPlaying(text)
    emitSpeech()
  }

  private func stopSpeaking() {
    speech.stopSpeaking(at: .immediate)
    speechPartID = nil
    speechText = nil
    speechActive = false
    speechPaused = false
    setAudio(active: false)
    nowPlaying()
    emitSpeech()
  }

  private func pauseSpeaking() {
    if speechActive, speech.isSpeaking {
      speech.pauseSpeaking(at: .word)
    }
    if speechActive {
      speechPaused = true
    }
    emitSpeech()
  }

  private func resumeSpeaking() {
    if speechActive, speech.isPaused {
      setAudio(active: true)
      speech.continueSpeaking()
    }
    if speechActive {
      speechPaused = false
    }
    emitSpeech()
  }
}

@MainActor
extension PlatformBridge {
  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if speech.isSpeaking { return }
      speechPartID = nil
      speechText = nil
      speechActive = false
      speechPaused = false
      setAudio(active: false)
      emitSpeech()
    }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if speech.isSpeaking || speech.isPaused { return }
      speechPartID = nil
      speechText = nil
      speechActive = false
      speechPaused = false
      setAudio(active: false)
      emitSpeech()
    }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if speechActive {
        speechPaused = true
      }
      emitSpeech()
    }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
    Task { @MainActor in
      if speechActive {
        speechPaused = false
      }
      emitSpeech()
    }
  }
}
