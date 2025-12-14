import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let openCVChannel = FlutterMethodChannel(
      name: "com.example.guinness_glass/opencv",
      binaryMessenger: controller.binaryMessenger
    )
    
    openCVChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "analyzeImage" {
        guard let args = call.arguments as? [String: Any],
              let imagePath = args["imagePath"] as? String else {
          result(FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Image path is required",
            details: nil
          ))
          return
        }
        
        let level = OpenCVProcessor.analyzeImage(imagePath: imagePath)
        result(level)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
