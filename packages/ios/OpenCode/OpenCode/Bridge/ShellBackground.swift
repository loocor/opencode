import UIKit
import WebKit

enum ShellBackground {
  @MainActor
  static func apply(cssColor: String, webView: WKWebView?) {
    guard let color = UIColor(cssColor: cssColor) else { return }
    if let window = resolveWindow(webView: webView) {
      window.backgroundColor = color
      window.rootViewController?.view.backgroundColor = color
    }
    guard let webView else { return }
    webView.underPageBackgroundColor = color
  }

  @MainActor
  private static func resolveWindow(webView: WKWebView?) -> UIWindow? {
    if let window = webView?.window {
      return window
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      if let key = windowScene.windows.first(where: \.isKeyWindow) {
        return key
      }
      if let normal = windowScene.windows.first(where: { $0.windowLevel == .normal }) {
        return normal
      }
    }
    return nil
  }
}

private extension UIColor {
  convenience init?(cssColor: String) {
    let raw = cssColor.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = raw.lowercased()
    if lower.hasPrefix("#") {
      self.init(hexDigits: String(lower.dropFirst()))
      return
    }
    if lower.hasPrefix("rgb") {
      self.init(rgbFunction: raw)
      return
    }
    return nil
  }

  convenience init?(hexDigits: String) {
    var digits = hexDigits
    if digits.count == 3 {
      digits = digits.map { String([$0, $0]) }.joined()
    }
    guard digits.count == 6 || digits.count == 8 else { return nil }
    var value: UInt64 = 0
    guard Scanner(string: digits).scanHexInt64(&value) else { return nil }
    if digits.count == 6 {
      self.init(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: 1
      )
      return
    }
    self.init(
      red: CGFloat((value >> 24) & 0xFF) / 255,
      green: CGFloat((value >> 16) & 0xFF) / 255,
      blue: CGFloat((value >> 8) & 0xFF) / 255,
      alpha: CGFloat(value & 0xFF) / 255
    )
  }

  convenience init?(rgbFunction: String) {
    let pattern = #"rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: rgbFunction, range: NSRange(rgbFunction.startIndex..., in: rgbFunction)),
          match.numberOfRanges >= 4
    else { return nil }

    func component(at idx: Int) -> CGFloat? {
      guard let range = Range(match.range(at: idx), in: rgbFunction) else { return nil }
      return CGFloat(Double(rgbFunction[range]) ?? 0)
    }

    guard let red = component(at: 1),
          let green = component(at: 2),
          let blue = component(at: 3)
    else { return nil }
    let alpha: CGFloat
    if match.numberOfRanges > 4, match.range(at: 4).location != NSNotFound, let parsed = component(at: 4) {
      alpha = parsed
    } else {
      alpha = 1
    }
    self.init(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
  }
}
