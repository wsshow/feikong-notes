import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var liteRtLmBridge: LiteRtLmBridge?
  private var audioDecodeBridge: AudioDecodeBridge?
  private var externalImageDropBridge: ExternalImageDropBridge?
  private var incomingShareBridge: IncomingShareBridge?
  private var fileExportBridge: FileExportBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let started = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    return started
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    NoteReminderBridge.shared.attach(messenger: engineBridge.applicationRegistrar.messenger())
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    liteRtLmBridge = LiteRtLmBridge(messenger: engineBridge.applicationRegistrar.messenger())
    audioDecodeBridge = AudioDecodeBridge(messenger: engineBridge.applicationRegistrar.messenger())
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FknotesImageDrop") {
      externalImageDropBridge = ExternalImageDropBridge(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FknotesIncomingShare") {
      incomingShareBridge = IncomingShareBridge(registrar: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FknotesFileExport") {
      fileExportBridge = FileExportBridge(registrar: registrar)
    }
  }
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if NoteReminderBridge.shared.owns(response.notification) {
      NoteReminderBridge.shared.opened(response)
      completionHandler()
    } else { super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if NoteReminderBridge.shared.owns(notification) { completionHandler([.banner, .list, .sound]) }
    else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }

}
