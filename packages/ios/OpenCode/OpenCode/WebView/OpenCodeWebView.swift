import SwiftUI
import WebKit

struct OpenCodeWebView: UIViewRepresentable {
  func makeCoordinator() -> BridgeController {
    BridgeController()
  }

  func makeUIView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: context.coordinator.configuration)
    webView.inputAssistantItem.leadingBarButtonGroups = []
    webView.inputAssistantItem.trailingBarButtonGroups = []
    context.coordinator.attach(to: webView)
    return webView
  }

  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
