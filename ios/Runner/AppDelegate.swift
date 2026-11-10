import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var audioDecodeBridge: AudioDecodeBridge?
  private var fileExportBridge: FileExportBridge?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    audioDecodeBridge = AudioDecodeBridge(messenger: engineBridge.applicationRegistrar.messenger())
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FknotesFileExport") {
      fileExportBridge = FileExportBridge(registrar: registrar)
    }
  }
}
