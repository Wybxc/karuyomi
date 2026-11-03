import UIKit
import WebKit
import CryptoKit
import ImageIO

/// Isolated public-API mechanism probe. This is not the product's adapter.
final class ProbeController: UIViewController, WKNavigationDelegate,
                             WKScriptMessageHandler, WKDownloadDelegate {
    struct ProbeCase {
        let id: String
        let mode: String
        let bytes: Int
        let cancel: Bool
    }
    private let cases = [
        ProbeCase(id: "binary-256k", mode: "binary", bytes: 256 * 1024, cancel: false),
        ProbeCase(id: "binary-4m", mode: "binary", bytes: 4 * 1024 * 1024, cancel: false),
        ProbeCase(id: "binary-16m", mode: "binary", bytes: 16 * 1024 * 1024, cancel: false),
        ProbeCase(id: "processed-png", mode: "png", bytes: 0, cancel: false),
        ProbeCase(id: "cancel-16m", mode: "binary", bytes: 16 * 1024 * 1024, cancel: true),
    ]
    private var webView: WKWebView!
    private let console = UITextView()
    private var index = 0
    private var activeDownload: WKDownload?
    private var expected: [String: Any] = [:]
    private var destination: URL?
    private var results: [[String: Any]] = []
    private var started = Date()
    private var report: [String: Any] = [
        "probe": "ios-wkdownload-blob-v1", "transport": "WKWebView.startDownload(blob)",
        "platform": "iOS", "productionHTTPSVerified": false, "physicalDeviceVerified": false,
        "memoryPeakMeasured": false,
    ]
    private lazy var root: URL = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("karuyomi-resource-probe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(self, name: "resourceProbe")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        console.isEditable = false
        let stack = UIStackView(arrangedSubviews: [console, webView])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.heightAnchor.constraint(equalToConstant: 120),
        ])
        report["systemVersion"] = UIDevice.current.systemVersion
        #if targetEnvironment(simulator)
        report["environment"] = "simulator"
        #else
        report["environment"] = "device"
        #endif
        let arguments = ProcessInfo.processInfo.arguments
        let urlIndex = arguments.firstIndex(of: "-probeURL")
        let urlString = urlIndex.flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
            ?? "http://127.0.0.1:29842/index.html"
        report["pageURL"] = urlString
        guard let url = URL(string: urlString) else { fail("Invalid probe URL"); return }
        webView.load(URLRequest(url: url))
        DispatchQueue.main.asyncAfter(deadline: .now() + 90) { [weak self] in
            guard let self = self, self.report["complete"] as? Bool != true else { return }
            self.fail("Probe timed out")
        }
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        if type == "ready" {
            report["secureContext"] = body["secureContext"]
            report["origin"] = body["origin"]
            runNext()
        } else if type == "error" {
            fail(body["message"] as? String ?? "Worker error")
        } else if type == "resource" {
            beginDownload(body)
        }
    }

    private func runNext() {
        guard index < cases.count else {
            report["complete"] = true
            report["passed"] = results.allSatisfy { $0["passed"] as? Bool == true }
            report["remainingFiles"] = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            saveReport()
            return
        }
        expected = [:]
        destination = nil
        started = Date()
        let item = cases[index]
        let request: [String: Any] = ["id": item.id, "mode": item.mode, "byteLength": item.bytes]
        let data = try! JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        let json = String(data: data, encoding: .utf8)!
        webView.evaluateJavaScript("window.resourceProbe.run(\(json))") { [weak self] _, error in
            if let error = error { self?.fail("JS request failed: \(error)") }
        }
    }

    private func beginDownload(_ body: [String: Any]) {
        guard index < cases.count, activeDownload == nil,
              body["id"] as? String == cases[index].id,
              body["workerBufferDetached"] as? Bool == true,
              let bytes = body["byteLength"] as? Int, bytes > 0, bytes <= 32 * 1024 * 1024,
              let string = body["url"] as? String,
              let origin = report["origin"] as? String,
              string.hasPrefix("blob:\(origin)/"),
              let url = URL(string: string), url.scheme == "blob"
        else { fail("Invalid or unexpected resource control message"); return }
        expected = body
        webView.startDownload(using: URLRequest(url: url)) { [weak self] download in
            guard let self = self else { download.cancel(nil); return }
            self.activeDownload = download
            download.delegate = self
            if self.cases[self.index].cancel {
                download.cancel { [weak self] _ in self?.finishCancellation() }
            }
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard download === activeDownload, !cases[index].cancel,
              response.expectedContentLength < 0 || response.expectedContentLength <= 32 * 1024 * 1024
        else { completionHandler(nil); return }
        let file = root.appendingPathComponent(UUID().uuidString)
        destination = file
        completionHandler(file)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard download === activeDownload, let file = destination else { return }
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hasher = SHA256()
            var count = 0
            while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                count += chunk.count
                guard count <= 32 * 1024 * 1024 else { fail("File exceeds budget"); return }
                hasher.update(data: chunk)
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            var result: [String: Any] = [
                "id": cases[index].id, "status": "downloaded", "byteLength": count,
                "sha256": digest, "workerSha256": expected["sha256"] ?? "",
                "workerBufferDetached": expected["workerBufferDetached"] ?? false,
                "durationMs": Date().timeIntervalSince(started) * 1000,
            ]
            var imageVerified = true
            if cases[index].mode == "png" {
                let image = CGImageSourceCreateWithURL(file as CFURL, nil)
                let properties = image.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] }
                let width = properties?[kCGImagePropertyPixelWidth as String] as? Int
                let height = properties?[kCGImagePropertyPixelHeight as String] as? Int
                imageVerified = width == 128 && height == 256
                result["imageWidth"] = width
                result["imageHeight"] = height
            }
            result["passed"] = digest == expected["sha256"] as? String && count == expected["byteLength"] as? Int && imageVerified
            try FileManager.default.removeItem(at: file)
            result["fileReleased"] = !FileManager.default.fileExists(atPath: file.path)
            finish(result)
        } catch { fail("File verification failed: \(error)") }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard download === activeDownload else { return }
        if cases[index].cancel { return }
        fail("WKDownload failed: \(error)")
    }

    private func finishCancellation() {
        if let file = destination { try? FileManager.default.removeItem(at: file) }
        finish([
            "id": cases[index].id, "status": "cancelled", "passed": true,
            "fileReleased": destination.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true,
        ])
    }

    private func finish(_ result: [String: Any]) {
        activeDownload?.delegate = nil
        activeDownload = nil
        results.append(result)
        saveReport()
        let id = cases[index].id
        let data = try! JSONSerialization.data(withJSONObject: id, options: [.fragmentsAllowed])
        let json = String(data: data, encoding: .utf8)!
        webView.evaluateJavaScript("window.resourceProbe.release(\(json))") { [weak self] value, error in
            guard let self = self else { return }
            guard error == nil, (value as? Int) == 0 else { self.fail("Blob resource release failed"); return }
            self.results[self.results.count - 1]["blobReleased"] = true
            self.index += 1
            self.runNext()
        }
    }

    private func fail(_ message: String) {
        activeDownload?.cancel(nil)
        activeDownload = nil
        if let file = destination { try? FileManager.default.removeItem(at: file) }
        report["complete"] = true
        report["passed"] = false
        report["error"] = message
        saveReport()
    }

    private func saveReport() {
        report["results"] = results
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("resource-probe-report.json")
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file, options: .atomic)
            console.text = String(data: data, encoding: .utf8)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail("Page load failed: \(error)")
    }
}
