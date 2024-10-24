import Flutter
import UIKit
import Vision
import VisionKit
@available(iOS 13.0, *)
public class SwiftCunningDocumentScannerPlugin: NSObject, FlutterPlugin, VNDocumentCameraViewControllerDelegate {
    var resultChannel: FlutterResult?
    weak var presentingController: VNDocumentCameraViewController?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "cunning_document_scanner", binaryMessenger: registrar.messenger())
        let instance = SwiftCunningDocumentScannerPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "getPictures" {
            guard let presentedVC = UIApplication.shared.keyWindow?.rootViewController else {
                result(FlutterError(code: "NO_ROOT_VC", message: "No root view controller found", details: nil))
                return
            }
            self.resultChannel = result
            if VNDocumentCameraViewController.isSupported {
                let documentCameraViewController = VNDocumentCameraViewController()
                documentCameraViewController.delegate = self
                self.presentingController = documentCameraViewController
                let navigationController = UINavigationController(rootViewController: documentCameraViewController)
                navigationController.presentationController?.delegate = self
                presentedVC.present(navigationController, animated: true, completion: nil)
            } else {
                result(FlutterError(code: "UNAVAILABLE", message: "Document camera is not available on this device", details: nil))
            }
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    func getDocumentsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0]
    }
    
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        let tempDirPath = self.getDocumentsDirectory()
        let currentDateTime = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let formattedDate = df.string(from: currentDateTime)
        var filenames: [String] = []
        
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else { return }
            
            for i in 0 ..< scan.pageCount {
                autoreleasepool {
                    let page = scan.imageOfPage(at: i)
                    let url = tempDirPath.appendingPathComponent(formattedDate + "-\(i).png")
                    do {
                        try page.pngData()?.write(to: url)
                        filenames.append(url.path)
                    } catch {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.resultChannel?(FlutterError(code: "WRITE_ERROR", message: "Failed to write image data to file", details: error.localizedDescription))
                        }
                        return
                    }
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.resultChannel?(filenames)
                self.presentingController?.dismiss(animated: true) {
                    self.presentingController = nil
                }
            }
        }
    }
    
    public func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        resultChannel?(nil)
        presentingController?.dismiss(animated: true) { [weak self] in
            self?.presentingController = nil
        }
    }
    
    public func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        resultChannel?(FlutterError(code: "ERROR", message: error.localizedDescription, details: nil))
        presentingController?.dismiss(animated: true) { [weak self] in
            self?.presentingController = nil
        }
    }
}
extension SwiftCunningDocumentScannerPlugin: UIAdaptivePresentationControllerDelegate {
    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        resultChannel?(FlutterError(code: "CANCELLED", message: "Document scanning cancelled", details: nil))
        self.presentingController = nil
    }
}
