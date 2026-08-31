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
    let shareChannel = FlutterMethodChannel(
      name: "com.filmswipe.app/share",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    shareChannel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareText" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard
        let arguments = call.arguments as? [String: Any],
        let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
        !text.isEmpty
      else {
        result(FlutterError(code: "invalid-argument", message: "No hay contenido para compartir.", details: nil))
        return
      }

      DispatchQueue.main.async {
        guard let viewController = self?.topViewController() else {
          result(FlutterError(code: "unavailable", message: "No se pudo abrir el menú para compartir.", details: nil))
          return
        }

        let activityController = UIActivityViewController(
          activityItems: [text],
          applicationActivities: nil
        )
        if let popover = activityController.popoverPresentationController {
          popover.sourceView = viewController.view
          popover.sourceRect = CGRect(
            x: viewController.view.bounds.midX,
            y: viewController.view.bounds.midY,
            width: 0,
            height: 0
          )
        }
        viewController.present(activityController, animated: true)
        result(nil)
      }
    }
  }

  private func topViewController() -> UIViewController? {
    let rootViewController = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow }?
      .rootViewController
    return visibleViewController(from: rootViewController)
  }

  private func visibleViewController(from viewController: UIViewController?) -> UIViewController? {
    if let navigationController = viewController as? UINavigationController {
      return visibleViewController(from: navigationController.visibleViewController)
    }
    if let tabBarController = viewController as? UITabBarController {
      return visibleViewController(from: tabBarController.selectedViewController)
    }
    if let presentedViewController = viewController?.presentedViewController {
      return visibleViewController(from: presentedViewController)
    }
    return viewController
  }
}
