import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ShuSystem") {
      ScreenDimmer.shared.listen(to: registrar.messenger())
    }
  }
}

/// Driving mode's dimmed black screen (`screenBrightness` on the app's system channel, as on
/// Android). iOS has one brightness for the whole device, not one per app window, so the user's
/// own is kept and given back on leaving, and also whenever Shu is not in front: the device never
/// stays dark because of Shu.
final class ScreenDimmer: NSObject {
  static let shared = ScreenDimmer()

  /// The brightness asked for, while driving mode is dark.
  private var dimmed: CGFloat?
  /// The user's own brightness, while Shu has changed it.
  private var saved: CGFloat?

  func listen(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "io.player.shu/downloads", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "screenBrightness" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.set((call.arguments as? NSNumber).map { CGFloat($0.doubleValue) })
      result(nil)
    }
    let center = NotificationCenter.default
    center.addObserver(
      self, selector: #selector(away), name: UIApplication.willResignActiveNotification, object: nil)
    center.addObserver(
      self, selector: #selector(back), name: UIApplication.didBecomeActiveNotification, object: nil)
  }

  private func set(_ value: CGFloat?) {
    if let value = value {
      if saved == nil { saved = UIScreen.main.brightness }
      dimmed = value
      UIScreen.main.brightness = value
    } else {
      dimmed = nil
      giveBack()
    }
  }

  private func giveBack() {
    if let saved = saved { UIScreen.main.brightness = saved }
    saved = nil
  }

  @objc private func away() {
    if dimmed != nil { giveBack() }
  }

  @objc private func back() {
    guard let dimmed = dimmed else { return }
    saved = UIScreen.main.brightness
    UIScreen.main.brightness = dimmed
  }
}
