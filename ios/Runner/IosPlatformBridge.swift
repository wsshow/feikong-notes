import Flutter
import UIKit

final class IosPlatformBridge {
  private let channel: FlutterMethodChannel
  private let localeChannel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "fknotes/ios_platform", binaryMessenger: messenger)
    localeChannel = FlutterMethodChannel(name: "fknotes/app_locale", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "configureStorage":
        do {
          // The native side derives its own container. Dart cannot nominate an
          // arbitrary path, and backup restore never replaces this root.
          var root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
          try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
          var values = URLResourceValues()
          values.isExcludedFromBackup = true
          try root.setResourceValues(values)
          try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
          result(nil)
        } catch { result(FlutterError(code: "storage_policy_failed", message: nil, details: nil)) }
      case "privacyReady":
        NotificationCenter.default.post(name: .fknotesPrivacyReady, object: nil)
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    localeChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getApplicationLocale":
        // Flutter's stored preference remains authoritative, including restores.
        result(nil)
      case "setApplicationLocale":
        guard let tag = call.arguments as? String, ["", "en", "zh-Hans"].contains(tag) else {
          result(FlutterError(code: "invalid_locale", message: nil, details: nil)); return
        }
        NativeStrings.setLanguage(tag)
        NoteReminderBridge.shared.refreshLanguage()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

extension Notification.Name {
  static let fknotesPrivacyReady = Notification.Name("fknotes.privacyReady")
}
