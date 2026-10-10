import Flutter
import UIKit
import AudioToolbox
import Photos
import PhotosUI

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var videoHandler: VideoHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    // Таймер отдыха: экран не гаснет, пока идёт отсчёт, и вибрация по концу.
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

    // Видео: штатная камера, открытие, шаринг, удаление файла.
    let handler = VideoHandler()
    videoHandler = handler
    let videoChannel = FlutterMethodChannel(name: "workout/video", binaryMessenger: messenger)
    videoChannel.setMethodCallHandler { call, result in
      handler.handle(call, result: result)
    }
  }
}

/// Штатная камера для видео и работа с записанным файлом.
///
/// На iOS файл из камеры живёт во временной папке — поэтому мы ВСЕГДА
/// переносим его в папку Documents/WorkoutLog (память приложения) и
/// возвращаем приложению этот путь. Если выбрана «Галерея», сверху
/// кладём копию в Фотоальбом; удаление приложения уберёт наш файл,
/// но копия в Фото останется.
class VideoHandler: NSObject, UIImagePickerControllerDelegate,
    UINavigationControllerDelegate {
  private var pendingResult: FlutterResult?
  private var toGallery = false
  private var picker: UIImagePickerController?
  private var phPicker: PHPickerViewController?
  private var docController: UIDocumentInteractionController?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "record":
      startRecord(call, result: result)
    case "pick":
      startPick(result)
    case "open":
      openVideo(call, result: result)
    case "share":
      shareVideo(call, result: result)
    case "delete":
      deleteVideo(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Камера

  private func startRecord(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
      result(FlutterError(
        code: "no_camera", message: "На этом телефоне нет камеры", details: nil))
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(
        code: "busy", message: "Камера уже открыта", details: nil))
      return
    }
    pendingResult = result
    let args = call.arguments as? [String: Any]
    toGallery = args?["toGallery"] as? Bool ?? true

    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.mediaTypes = ["public.movie"]
    picker.videoQuality = .typeHigh
    picker.delegate = self
    self.picker = picker
    DispatchQueue.main.async {
      self.topViewController()?.present(picker, animated: true)
    }
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    let url = info[.mediaURL] as? URL
    picker.dismiss(animated: true) { [weak self] in
      self?.finishRecord(url: url)
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true) { [weak self] in
      guard let self = self else { return }
      let r = self.pendingResult
      self.pendingResult = nil
      self.picker = nil
      r?(nil)
    }
  }

  private func finishRecord(url: URL?) {
    let r = pendingResult
    pendingResult = nil
    picker = nil
    guard let url = url else {
      r?(nil)
      return
    }

    // Переносим во временнике в свою папку — путь должен жить долго.
    let dest = Self.workoutDir().appendingPathComponent(
      "WL_\(Int(Date().timeIntervalSince1970)).mp4")
    do {
      try FileManager.default.createDirectory(
        at: Self.workoutDir(), withIntermediateDirectories: true)
      try FileManager.default.moveItem(at: url, to: dest)
    } catch {
      // Не вышло перенести — отдаём путь как есть, он тоже работает.
      r?(url.path)
      return
    }

    if toGallery {
      saveToGallery(path: dest.path)
    }
    r?(dest.path)
  }

  private func saveToGallery(path: String) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else { return }
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: URL(fileURLWithPath: path))
      })
    }
  }

  // MARK: - Выбор готового видео

  /// iOS отдаёт выбранный файл только во временной папке — поэтому
  /// копируем его в Documents/WorkoutLog и возвращаем этот путь.
  private func startPick(_ result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "busy", message: "Окно уже открыто", details: nil))
      return
    }
    pendingResult = result
    var config = PHPickerConfiguration()
    config.filter = .videos
    config.selectionLimit = 1
    let picker = PHPickerViewController(configuration: config)
    picker.delegate = self
    phPicker = picker
    DispatchQueue.main.async {
      self.topViewController()?.present(picker, animated: true)
    }
  }

  private func finishPick(url: URL?) {
    let r = pendingResult
    pendingResult = nil
    phPicker = nil
    guard let url = url else {
      r?(nil)
      return
    }
    let dest = Self.workoutDir().appendingPathComponent(
      "WL_\(Int(Date().timeIntervalSince1970)).mp4")
    do {
      try FileManager.default.createDirectory(
        at: Self.workoutDir(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: url, to: dest)
      r?(dest.path)
    } catch {
      r?(FlutterError(code: "pick", message: "Не получилось прочитать видео", details: nil))
    }
  }

  /// Копия делается в потоке колбэка (файл из выборщика живёт только там),
  /// а результат и чистка состояния — в главном потоке.
  private func copyPickedFile(url: URL, result r: FlutterResult) {
    let dest = Self.workoutDir().appendingPathComponent(
      "WL_\(Int(Date().timeIntervalSince1970)).mp4")
    var errorText: String?
    do {
      try FileManager.default.createDirectory(
        at: Self.workoutDir(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: url, to: dest)
    } catch {
      errorText = "Не получилось прочитать видео"
    }
    DispatchQueue.main.async {
      self.pendingResult = nil
      self.phPicker = nil
      if let errorText = errorText {
        r(FlutterError(code: "pick", message: errorText, details: nil))
      } else {
        r(dest.path)
      }
    }
  }

  // MARK: - Открытие, шаринг, удаление

  private func openVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let path = args?["path"] as? String ?? ""
    let url = URL(fileURLWithPath: path)
    DispatchQueue.main.async {
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(
          code: "open", message: "Файл видео не найден — возможно, он удалён", details: nil))
        return
      }
      let controller = UIDocumentInteractionController(url: url)
      controller.delegate = self
      self.docController = controller
      let top = self.topViewController()
      if top == nil || !controller.presentPreview(from: top!) {
        result(FlutterError(
          code: "open", message: "Не получилось открыть видео", details: nil))
        return
      }
      result(nil)
    }
  }

  private func shareVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let path = args?["path"] as? String ?? ""
    DispatchQueue.main.async {
      guard FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(
          code: "share", message: "Файл видео не найден — возможно, он удалён", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
      if let pop = activity.popoverPresentationController, let top = self.topViewController() {
        pop.sourceView = top.view
        pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        pop.permittedArrowDirections = []
      }
      self.topViewController()?.present(activity, animated: true)
      result(nil)
    }
  }

  private func deleteVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let path = args?["path"] as? String ?? ""
    do {
      try FileManager.default.removeItem(atPath: path)
      result(true)
    } catch {
      result(false)
    }
  }

  // MARK: - Помощники

  private static func workoutDir() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return docs.appendingPathComponent("WorkoutLog", isDirectory: true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

extension VideoHandler: UIDocumentInteractionControllerDelegate {
  func documentInteractionControllerDidEndPreview(
    _ controller: UIDocumentInteractionController
  ) {
    docController = nil
  }
}

extension VideoHandler: PHPickerViewControllerDelegate {
  func picker(
    _ picker: PHPickerViewController,
    didFinishPicking results: [PHPickerResult]
  ) {
    picker.dismiss(animated: true)
    guard let r = pendingResult,
          let item = results.first?.itemProvider,
          item.hasItemConformingToTypeIdentifier("public.movie") else {
      finishPick(url: nil)
      return
    }
    item.loadFileRepresentation(forTypeIdentifier: "public.movie") { url, _ in
      guard let url = url else {
        DispatchQueue.main.async {
          self.pendingResult = nil
          self.phPicker = nil
          r(nil)
        }
        return
      }
      self.copyPickedFile(url: url, result: r)
    }
  }
}
