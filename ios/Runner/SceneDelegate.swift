import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    NotificationCenter.default.addObserver(self, selector: #selector(revealProtectedFrame), name: .fknotesPrivacyReady, object: nil)
    if let response = connectionOptions.notificationResponse, NoteReminderBridge.shared.owns(response.notification) {
      NoteReminderBridge.shared.opened(response)
    }
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    // Install before Flutter's asynchronous privacy frame and the OS snapshot.
    if let window, privacyCover == nil {
      let cover = UIView(frame: window.bounds)
      cover.backgroundColor = .systemBackground
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      cover.isAccessibilityElement = false
      window.addSubview(cover)
      privacyCover = cover
    }
    super.sceneWillResignActive(scene)
  }

  @objc private func revealProtectedFrame() {
    guard window?.windowScene?.activationState == .foregroundActive else { return }
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }

  deinit { NotificationCenter.default.removeObserver(self) }

}
