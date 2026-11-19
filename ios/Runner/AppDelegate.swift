import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var screenGuard: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Chat privacy: tell Dart when the user takes a screenshot. iOS can't
    // block screenshots, so "setSecure" is a no-op here.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CloserScreenGuard") else { return }
    let channel = FlutterMethodChannel(name: "app.closer/screen_guard", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setSecure": result(false)
      case "canDetect": result(true)
      default: result(FlutterMethodNotImplemented)
      }
    }
    screenGuard = channel
    NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.screenGuard?.invokeMethod("screenshot", arguments: nil)
    }
  }
}
