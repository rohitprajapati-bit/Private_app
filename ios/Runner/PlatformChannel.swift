import AVFoundation
import Flutter
import ImageIO
import LocalAuthentication
import Security
import UIKit
import UniformTypeIdentifiers

/// Dart <-> Swift bridge. Method names and error codes must match
/// lib/platform/platform_channel.dart.
final class PlatformChannel: NSObject, FlutterPlugin {
  static let name = "color_match/platform"

  private let keychain = BiometricKeychain()
  private let privacyCover = PrivacyCover()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(PlatformChannel(), channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "biometricStatus":
      result(keychain.status())
    case "biometricEnable":
      guard let key = args["key"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "failed", message: nil, details: nil))
        return
      }
      keychain.enable(masterKey: key.data, reason: args["title"] as? String ?? "", completion: result)
    case "biometricUnlock":
      keychain.unlock(reason: args["title"] as? String ?? "", completion: result)
    case "biometricDisable":
      keychain.disable()
      result(nil)
    case "setSecureScreen":
      privacyCover.isEnabled = args["enabled"] as? Bool ?? false
      result(nil)
    case "mediaInfo":
      guard let path = args["path"] as? String else {
        result(nil)
        return
      }
      let isVideo = args["isVideo"] as? Bool ?? false
      let maxSize = args["maxSize"] as? Int ?? 400
      DispatchQueue.global(qos: .userInitiated).async {
        let info = isVideo
          ? MediaThumbnailer.describeVideo(path: path, maxSize: maxSize)
          : MediaThumbnailer.describeImage(path: path, maxSize: maxSize)
        DispatchQueue.main.async { result(info) }
      }
    case "transcodeToJpeg":
      guard let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(nil)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let jpeg = MediaThumbnailer.transcodeToJpeg(bytes.data)
        DispatchQueue.main.async { result(jpeg.map { FlutterStandardTypedData(bytes: $0) }) }
      }
    case "excludeFromBackup":
      guard let path = args["path"] as? String else {
        result(nil)
        return
      }
      var url = URL(fileURLWithPath: path)
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

/// Stores the vault master key in a Keychain item that iOS releases only after Face ID /
/// Touch ID (or the device passcode as fallback). The item never syncs and never leaves the device.
private final class BiometricKeychain {
  private let service = "com.furation.colormatch.vault"
  private let account = "biometric-master-key"

  func status() -> [String: Any] {
    let context = LAContext()
    var error: NSError?
    let available = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    let kind: String
    switch context.biometryType {
    case .faceID: kind = "face"
    case .touchID: kind = "fingerprint"
    default: kind = "passcode"
    }
    return ["available": available, "enabled": itemExists(), "kind": kind]
  }

  func enable(masterKey: Data, reason: String, completion: @escaping FlutterResult) {
    // Confirm the owner is present before storing (also triggers the Face ID permission prompt).
    LAContext().evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
      DispatchQueue.main.async {
        guard success else {
          completion(FlutterError(code: Self.code(for: error), message: nil, details: nil))
          return
        }
        self.disable()
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
          nil,
          kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
          [.biometryCurrentSet, .or, .devicePasscode],
          &acError
        ) else {
          completion(FlutterError(code: "unavailable", message: nil, details: nil))
          return
        }
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: self.service,
          kSecAttrAccount as String: self.account,
          kSecAttrAccessControl as String: access,
          kSecAttrSynchronizable as String: false,
          kSecValueData as String: masterKey,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
          completion(nil)
        } else {
          completion(FlutterError(code: "unavailable", message: nil, details: nil))
        }
      }
    }
  }

  func unlock(reason: String, completion: @escaping FlutterResult) {
    let context = LAContext()
    context.localizedReason = reason
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecUseAuthenticationContext as String: context,
    ]
    // SecItemCopyMatching blocks while the Face ID sheet is up, so keep it off the main thread.
    DispatchQueue.global(qos: .userInitiated).async {
      var item: CFTypeRef?
      let status = SecItemCopyMatching(query as CFDictionary, &item)
      DispatchQueue.main.async {
        switch status {
        case errSecSuccess:
          if let data = item as? Data {
            completion(FlutterStandardTypedData(bytes: data))
          } else {
            completion(FlutterError(code: "failed", message: nil, details: nil))
          }
        case errSecUserCanceled:
          completion(FlutterError(code: "cancelled", message: nil, details: nil))
        case errSecItemNotFound:
          completion(FlutterError(code: "notEnabled", message: nil, details: nil))
        default:
          completion(FlutterError(code: "failed", message: nil, details: nil))
        }
      }
    }
  }

  func disable() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }

  private func itemExists() -> Bool {
    let context = LAContext()
    context.interactionNotAllowed = true
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecUseAuthenticationContext as String: context,
    ]
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    // An item protected by biometrics reports "interaction not allowed" instead of returning it.
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  private static func code(for error: Error?) -> String {
    guard let laError = error as? LAError else { return "failed" }
    switch laError.code {
    case .userCancel, .appCancel, .systemCancel, .userFallback: return "cancelled"
    case .biometryLockout: return "lockout"
    case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet: return "unavailable"
    default: return "failed"
    }
  }
}

/// Covers the window while the app is inactive so the app-switcher snapshot never shows the vault.
private final class PrivacyCover {
  var isEnabled = false {
    didSet { if !isEnabled { hide() } }
  }
  private var cover: UIView?

  init() {
    let center = NotificationCenter.default
    center.addObserver(forName: UIScene.willDeactivateNotification, object: nil, queue: .main) { [weak self] _ in
      self?.show()
    }
    center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] _ in
      self?.hide()
    }
  }

  private func show() {
    guard isEnabled, cover == nil, let window = keyWindow() else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.backgroundColor = UIColor(red: 0x14 / 255, green: 0x12 / 255, blue: 0x2B / 255, alpha: 1)
    window.addSubview(view)
    cover = view
  }

  private func hide() {
    cover?.removeFromSuperview()
    cover = nil
  }

  private func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}

private enum MediaThumbnailer {
  static func describeImage(path: String, maxSize: Int) -> [String: Any?]? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil) else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    var width = props[kCGImagePropertyPixelWidth] as? Int
    var height = props[kCGImagePropertyPixelHeight] as? Int
    // EXIF orientations 5–8 are rotated by 90°.
    if let orientation = props[kCGImagePropertyOrientation] as? Int, orientation >= 5 {
      swap(&width, &height)
    }
    return [
      "thumbnail": thumbnail(source: source, maxSize: maxSize).map { FlutterStandardTypedData(bytes: $0) },
      "durationMs": nil,
      "width": width,
      "height": height,
    ]
  }

  static func describeVideo(path: String, maxSize: Int) -> [String: Any?]? {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxSize, height: maxSize)
    let seconds = CMTimeGetSeconds(asset.duration)
    let time = CMTime(seconds: seconds > 2 ? 1 : 0, preferredTimescale: 600)
    var jpeg: Data?
    if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
      jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.82)
    }
    var width: Int?
    var height: Int?
    if let track = asset.tracks(withMediaType: .video).first {
      let size = track.naturalSize.applying(track.preferredTransform)
      width = Int(abs(size.width))
      height = Int(abs(size.height))
    }
    return [
      "thumbnail": jpeg.map { FlutterStandardTypedData(bytes: $0) },
      "durationMs": seconds.isFinite ? Int(seconds * 1000) : nil,
      "width": width,
      "height": height,
    ]
  }

  /// Flutter cannot decode HEIC on iOS; convert in memory (never written to disk).
  static func transcodeToJpeg(_ data: Data) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    let exif = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
    let orientation = CGImagePropertyOrientation(rawValue: exif) ?? .up
    return UIImage(cgImage: image, scale: 1, orientation: UIImage.Orientation(orientation))
      .jpegData(compressionQuality: 0.92)
  }

  private static func thumbnail(source: CGImageSource, maxSize: Int) -> Data? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxSize,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    return UIImage(cgImage: image).jpegData(compressionQuality: 0.82)
  }
}

private extension UIImage.Orientation {
  init(_ cg: CGImagePropertyOrientation) {
    switch cg {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    }
  }
}
