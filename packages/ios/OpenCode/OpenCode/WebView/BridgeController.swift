import UIKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Local file scheme handler

final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
  private let baseDirectory: URL

  init(baseDirectory: URL) {
    self.baseDirectory = baseDirectory
  }

  func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
    guard let url = urlSchemeTask.request.url else {
      urlSchemeTask.didFailWithError(URLError(.badURL))
      return
    }

    // Map the URL path to a local file
    var path = url.path
    if path.isEmpty || path == "/" { path = "/index.html" }
    let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path

    var fileURL = baseDirectory.appendingPathComponent(relative)

    // SPA fallback: if the file doesn't exist and has no extension,
    // it's a client-side route — serve index.html instead
    if !FileManager.default.fileExists(atPath: fileURL.path) && fileURL.pathExtension.isEmpty {
      fileURL = baseDirectory.appendingPathComponent("index.html")
    }

    guard let data = try? Data(contentsOf: fileURL) else {
      print("[OpenCode] SchemeHandler 404: \(path)")
      urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
      return
    }

    let mimeType = Self.mimeType(for: fileURL.pathExtension)
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: "HTTP/1.1",
      headerFields: [
        "Content-Type": mimeType,
        "Content-Length": "\(data.count)",
        "Access-Control-Allow-Origin": "*"
      ]
    )!
    urlSchemeTask.didReceive(response)
    urlSchemeTask.didReceive(data)
    urlSchemeTask.didFinish()
  }

  func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

  private static let fallbackMimeByExtension: [String: String] = [
    "js": "application/javascript",
    "mjs": "application/javascript",
    "css": "text/css",
    "html": "text/html",
    "htm": "text/html",
    "json": "application/json",
    "svg": "image/svg+xml",
    "woff": "font/woff",
    "woff2": "font/woff2",
    "ttf": "font/ttf",
    "png": "image/png",
    "ico": "image/x-icon",
    "aac": "audio/aac",
    "webmanifest": "application/manifest+json"
  ]

  private static func mimeType(for ext: String) -> String {
    if let utType = UTType(filenameExtension: ext), let mime = utType.preferredMIMEType {
      return mime
    }
    return fallbackMimeByExtension[ext.lowercased()] ?? "application/octet-stream"
  }
}

// MARK: - Bridge Controller

final class BridgeController: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
  private let userContent = WKUserContentController()
  private let platform = PlatformBridge()
  private let gestures = GestureBridge()
  private weak var webView: WKWebView?
  private var schemeHandler: LocalFileSchemeHandler?
  private var keyboardObserver: NSObjectProtocol?

  var configuration: WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.userContentController = userContent

    // Simulator Debug can hit the Vite dev server. Physical devices and Release
    // builds must serve the bundled WebAssets via a custom scheme.
    if Self.shouldUseBundledAssets, let handler = Self.resolveWebAssets() {
      config.setURLSchemeHandler(handler, forURLScheme: "tauri")
      self.schemeHandler = handler
      print("[OpenCode] Registered tauri:// scheme handler")
    }

    return config
  }

  override init() {
    super.init()
    userContent.add(self, name: "opencode")
    platform.onEvent = { [weak self] type, payload in
      self?.sendEvent(type: type, payload: payload)
    }
  }

  func attach(to webView: WKWebView) {
    self.webView = webView
    webView.navigationDelegate = self
    suppressInputAssistant(for: webView)
    keyboardObserver = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillShowNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let webView = self?.webView else { return }
      self?.suppressInputAssistant(for: webView)
    }
    platform.webView = webView
    gestures.attach(to: webView) { [weak self] type, payload in
      self?.sendEvent(type: type, payload: payload)
    }
    loadStartPage(in: webView)
  }

  deinit {
    if let keyboardObserver {
      NotificationCenter.default.removeObserver(keyboardObserver)
    }
  }

  func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any] else { return }
    guard let id = body["id"] as? String else { return }
    guard let method = body["method"] as? String else { return }
    let params = body["params"] as? [String: Any] ?? [:]

    platform.handle(id: id, method: method, params: params) { [weak self] result, error in
      self?.sendResponse(id: id, result: result, error: error)
    }
  }

  private func loadStartPage(in webView: WKWebView) {
#if DEBUG
    // Local Vite only works for Simulator Debug while `bun run --cwd packages/ios dev` is up.
    if !Self.shouldUseBundledAssets, let url = URL(string: "http://localhost:1421") {
      print("[OpenCode] Loading Vite dev server: \(url.absoluteString)")
      webView.load(URLRequest(url: url))
      return
    }
#endif

    // Use tauri:// scheme to avoid file:// CORS restrictions with ES modules
    // and to piggyback on the server's default CORS whitelist for tauri://localhost
    if schemeHandler != nil, let url = URL(string: "tauri://localhost/") {
      print("[OpenCode] Loading via tauri:// scheme")
      webView.load(URLRequest(url: url))
      return
    }

    // Fallback to file:// if the custom scheme handler was not registered
    if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "WebAssets") {
      print("[OpenCode] Loading via file:// WebAssets")
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
      return
    }
    if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
      print("[OpenCode] Loading via file:// bundle root")
      webView.loadFileURL(url, allowingReadAccessTo: Bundle.main.bundleURL)
      return
    }
    print("[OpenCode] ERROR: Unable to locate start page")
  }

  private static var shouldUseBundledAssets: Bool {
#if DEBUG
#if targetEnvironment(simulator)
    return false
#else
    return true
#endif
#else
    return true
#endif
  }

  /// Locate web assets in the bundle and return a scheme handler for them
  private static func resolveWebAssets() -> LocalFileSchemeHandler? {
    let fileManager = FileManager.default
    let bundlePath = Bundle.main.bundlePath

    // Check for WebAssets subdirectory first (folder reference)
    let webAssetsDir = (bundlePath as NSString).appendingPathComponent("WebAssets")
    if fileManager.fileExists(atPath: (webAssetsDir as NSString).appendingPathComponent("index.html")) {
      print("[OpenCode] Serving from WebAssets/ subdirectory")
      return LocalFileSchemeHandler(baseDirectory: URL(fileURLWithPath: webAssetsDir))
    }

    // Flattened at bundle root
    if fileManager.fileExists(atPath: (bundlePath as NSString).appendingPathComponent("index.html")) {
      print("[OpenCode] Serving from bundle root (flattened)")
      return LocalFileSchemeHandler(baseDirectory: URL(fileURLWithPath: bundlePath))
    }

    print("[OpenCode] ERROR: No web assets found in bundle!")
    return nil
  }

  private func sendResponse(id: String, result: Any?, error: String?) {
    let payload: [Any] = [id, result ?? NSNull(), error ?? NSNull()]
    sendBridgeCall(function: "onResponse", payload: payload)
  }

  private func sendEvent(type: String, payload: Any?) {
    let payload: [Any] = [type, payload ?? NSNull()]
    sendBridgeCall(function: "onEvent", payload: payload)
  }

  private func sendBridgeCall(function: String, payload: [Any]) {
    guard let webView else { return }
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else { return }
    guard let json = String(data: data, encoding: .utf8) else { return }
    let script = "window.__OPENCODE_BRIDGE__ && window.__OPENCODE_BRIDGE__.\(function).apply(null, \(json))"
    webView.evaluateJavaScript(script, completionHandler: nil)
  }

  // MARK: - WKNavigationDelegate

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    print("[OpenCode] Loaded: \(webView.url?.absoluteString ?? "nil")")
    platform.webContentDidLoad()
  }

  func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
    print("[OpenCode] Load failed: \(error.localizedDescription)")
  }

  func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
    print("[OpenCode] Navigation failed: \(error.localizedDescription)")
  }

  private func suppressInputAssistant(for webView: WKWebView) {
    clearInputAssistant(on: webView)
    clearInputAssistant(on: webView.scrollView)
    webView.scrollView.subviews.forEach(clearInputAssistant)
  }

  private func clearInputAssistant(on view: UIView) {
    view.inputAssistantItem.leadingBarButtonGroups = []
    view.inputAssistantItem.trailingBarButtonGroups = []
    view.subviews.forEach(clearInputAssistant)
  }
}
