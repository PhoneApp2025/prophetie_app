import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  // MARK: - Sharing support via URL (Voice Memos / Files "Open in…")
  private let appGroupId = "group.com.simonnikel.phone"
  private var shareChannel: FlutterMethodChannel?

  /// Append a shared file path into the App Group defaults array ("shared_file_paths")
  private func appendSharedPath(_ path: String) {
    guard !path.isEmpty else { return }
    guard var defaults = UserDefaults(suiteName: appGroupId) else { return }
    var arr = defaults.stringArray(forKey: "shared_file_paths") ?? []
    // De-dupe: keep most recent, remove older same path
    arr.removeAll { $0 == path }
    arr.insert(path, at: 0)
    defaults.set(arr, forKey: "shared_file_paths")
  }

  /// Allow only audio files we know how to handle
  private func isAllowedAudio(_ url: URL) -> Bool {
    let allowedExts: Set<String> = ["m4a","mp3","wav","aac","aif","aiff","caf"]
    return url.isFileURL && allowedExts.contains(url.pathExtension.lowercased())
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // FlutterMethodChannel for sharing
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let shareChannel = FlutterMethodChannel(name: "com.simonnikel.phone/share",
                                           binaryMessenger: controller.binaryMessenger)
    self.shareChannel = shareChannel
    shareChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      if call.method == "fetchSharedFilePaths" {
        let appGroupId = "group.com.simonnikel.phone"

        // 1) Erst den direkten Weg: Liste aus App Group UserDefaults (von der Share Extension geschrieben)
        if let defaults = UserDefaults(suiteName: appGroupId),
           let recorded = defaults.stringArray(forKey: "shared_file_paths"),
           recorded.isEmpty == false {
          result(recorded)
          return
        }

        // 2) Fallback: Ordner scannen und nur Audio-Dateien zurückgeben
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
          result(FlutterError(code: "UNAVAILABLE",
                              message: "App group container not found",
                              details: nil))
          return
        }
        do {
          let audioExts: Set<String> = ["m4a","mp3","wav","aac","aif","aiff","caf"]
          let files = try FileManager.default.contentsOfDirectory(atPath: containerURL.path)
            .filter { name in
              let ext = (name as NSString).pathExtension.lowercased()
              return audioExts.contains(ext) || name.hasPrefix("Shared-")
            }
            .map { containerURL.appendingPathComponent($0).path }
          result(files)
        } catch {
          result(FlutterError(code: "UNAVAILABLE",
                              message: "Could not fetch files",
                              details: error.localizedDescription))
        }
      } else if call.method == "clearSharedFilePaths" {
        let appGroupId = "group.com.simonnikel.phone"
        if let defaults = UserDefaults(suiteName: appGroupId) {
          defaults.removeObject(forKey: "shared_file_paths")
        }
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // 3) Cold start via URL (open-in with file:)
    if let url = launchOptions?[.url] as? URL, isAllowedAudio(url) {
      appendSharedPath(url.path)
      // Nudge Flutter after launch so it can poll AppGroup immediately
      DispatchQueue.main.async { [weak self] in
        self?.shareChannel?.invokeMethod("wakeFromShare", arguments: nil)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called when the app is opened with a file: URL (e.g. Voice Memos / Files app)
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    // Persist into App Group so Flutter can fetch it via MethodChannel
    if isAllowedAudio(url) {
      appendSharedPath(url.path)
      // If Flutter is already running, wake it to fetch the file immediately
      self.shareChannel?.invokeMethod("wakeFromShare", arguments: nil)
      return true
    }
    // Not an allowed audio file; ignore and let super decide
    return super.application(app, open: url, options: options)
  }
}
