import Flutter
import UIKit
import AudioToolbox

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

    // Таймер отдыха: экран не гаснет, пока идёт отсчёт, и вибрация по концу.
    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(name: "workout/timer", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "keepScreenOn":
        let args = call.arguments as? [String: Any]
        let on = args?["on"] as? Bool ?? false
        DispatchQueue.main.async {
          UIApplication.shared.isIdleTimerDisabled = on
        }
        result(nil)
      case "notifyEnd":
        AudioServicesPlaySystemSound(1104)
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
