import CoreFoundation
import Flutter
import Foundation
import UIKit
import WebKit

struct NativeImageFailure: Error {
  let code: String
  let message: String

  var flutterError: FlutterError { FlutterError(code: code, message: message, details: nil) }
  static let cancelled = NativeImageFailure(
    code: "cancelled", message: "Image transfer was cancelled")
  static let lost = NativeImageFailure(
    code: "runtime_lost", message: "Native image container was lost")
}

struct NativeImageDescriptor {
  let requestId: String
  let resourceId: String
  let generation: String
  let url: URL
  let byteLength: Int

  var key: String { generation + "\0" + resourceId }

  static func identifier(_ value: Any?) throws -> String {
    guard let text = value as? String, !text.isEmpty, text.utf8.count <= 200,
      text.rangeOfCharacter(from: .controlCharacters) == nil
    else {
      throw NativeImageFailure(code: "protocol_error", message: "Invalid image identity")
    }
    return text
  }

  private static func positiveInteger(_ value: Any?, maximum: Int) throws -> Int {
    guard let number = value as? NSNumber,
      CFGetTypeID(number) != CFBooleanGetTypeID(),
      number.doubleValue.isFinite,
      number.doubleValue.rounded() == number.doubleValue,
      number.doubleValue > 0, number.doubleValue <= Double(maximum)
    else {
      throw NativeImageFailure(code: "protocol_error", message: "Invalid image size")
    }
    return number.intValue
  }

  init(_ input: [String: Any], origin: String) throws {
    requestId = try Self.identifier(input["requestId"])
    resourceId = try Self.identifier(input["resourceId"])
    generation = try Self.identifier(input["generation"])
    guard let text = input["url"] as? String, text.utf8.count <= 4096,
      let candidate = URL(string: text), candidate.scheme == "blob",
      let inner = URLComponents(string: String(text.dropFirst(5))),
      inner.query == nil, inner.fragment == nil,
      NativeImageFiles.httpsOrigin(inner.url) == origin,
      inner.path.count > 1
    else {
      throw NativeImageFailure(
        code: "protocol_error", message: "Only owned same-origin image Blobs can be transferred")
    }
    url = candidate
    byteLength = try Self.positiveInteger(input["byteLength"], maximum: 64 * 1024 * 1024)
  }
}

/// Reservations include pending downloads and retained files, across bindings.
final class NativeImageBudget {
  private(set) var resources = 0
  private(set) var bytes = 0

  func reserve(_ descriptor: NativeImageDescriptor) throws {
    guard resources < 6, bytes + descriptor.byteLength <= 64 * 1024 * 1024 else {
      throw NativeImageFailure(
        code: "limit_exceeded", message: "Native encoded resources exceed their shared budget")
    }
    resources += 1
    bytes += descriptor.byteLength
  }

  func release(_ descriptor: NativeImageDescriptor) {
    resources -= 1
    bytes -= descriptor.byteLength
  }
}

/// Extends the installed headless WebView with WKDownload, using only public API.
/// The locked plugin exposes neither its WKWebView registry nor startDownload.
final class NativeImageFiles: NSObject, FlutterPlugin {
  private let budget = NativeImageBudget()
  private var bindings: [String: NativeImageBinding] = [:]
  private var pendingBindings: [UUID: NativeImageBindAttempt] = [:]
  private var detached = false
  private let bindingGrace: TimeInterval
  private let candidateWebViews: () -> [WKWebView]
  private let storageDirectory: () throws -> URL
  private static var processDirectory: URL?

  init(
    bindingGrace: TimeInterval = 5,
    candidateWebViews: @escaping () -> [WKWebView] = NativeImageFiles.visibleWebViews,
    storageDirectory: @escaping () throws -> URL = NativeImageFiles.directory
  ) {
    self.bindingGrace = bindingGrace
    self.candidateWebViews = candidateWebViews
    self.storageDirectory = storageDirectory
    super.init()
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dev.karuyomi/native_image_files", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(NativeImageFiles(), channel: channel)
  }

  static func httpsOrigin(_ url: URL?) -> String? {
    guard let url, let input = URLComponents(url: url, resolvingAgainstBaseURL: false),
      input.scheme == "https", let host = input.host, !host.isEmpty,
      input.user == nil, input.password == nil
    else { return nil }
    var result = URLComponents()
    result.scheme = "https"
    result.host = host.lowercased()
    if let port = input.port, port != 443 { result.port = port }
    return result.url?.absoluteString
  }

  static func isControlPage(_ url: URL?, origin: String) -> Bool {
    guard let url, httpsOrigin(url) == origin,
      let input = URLComponents(url: url, resolvingAgainstBaseURL: false),
      ["/runtime/host", "/runtime/host.html"].contains(input.percentEncodedPath),
      url.query == nil, url.fragment == nil
    else { return false }
    return true
  }

  static func checkDirectory(_ directory: URL) throws {
    let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard values.isDirectory == true, values.isSymbolicLink != true else {
      throw NativeImageFailure(code: "runtime_lost", message: "Native image directory is invalid")
    }
  }

  private static func directory() throws -> URL {
    if let current = processDirectory {
      try checkDirectory(current)
      return current
    }
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
      "karuyomi-images", isDirectory: true)
    if FileManager.default.fileExists(atPath: base.path) {
      try checkDirectory(base)
      // Only the first bridge in this process removes crash leftovers.
      try FileManager.default.removeItem(at: base)
    }
    try FileManager.default.createDirectory(
      at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let current = base.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: current, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    processDirectory = current
    return current
  }

  private static func visibleWebViews() -> [WKWebView] {
    var result: [WKWebView] = []
    var seen = Set<ObjectIdentifier>()
    func visit(_ view: UIView) {
      guard seen.insert(ObjectIdentifier(view)).inserted else { return }
      if let webView = view as? WKWebView { result.append(webView) }
      for child in view.subviews { visit(child) }
    }
    for scene in UIApplication.shared.connectedScenes {
      if let windowScene = scene as? UIWindowScene {
        for window in windowScene.windows { visit(window) }
      }
    }
    return result
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 14.5, *) else {
      result(
        NativeImageFailure(
          code: "unsupported_capability", message: "Managed image files require iOS 14.5 or later"
        ).flutterError)
      return
    }
    guard !detached else {
      result(NativeImageFailure.lost.flutterError)
      return
    }
    guard let input = call.arguments as? [String: Any] else {
      result(
        NativeImageFailure(code: "protocol_error", message: "Image bridge arguments are missing")
          .flutterError)
      return
    }
    do {
      if call.method == "bind" {
        try bind(input, result: result)
        return
      }
      let id = try NativeImageDescriptor.identifier(input["bindingId"])
      let binding = bindings[id]
      switch call.method {
      case "acquire":
        guard let binding else { throw NativeImageFailure.lost }
        binding.acquire(try NativeImageDescriptor(input, origin: binding.origin), result: result)
      case "cancel":
        let request = try NativeImageDescriptor.identifier(input["requestId"])
        let generation = try NativeImageDescriptor.identifier(input["generation"])
        if let binding {
          binding.cancel(requestId: request, generation: generation, result: result)
        } else {
          result(["released": true])
        }
      case "release":
        let resource = try NativeImageDescriptor.identifier(input["resourceId"])
        let generation = try NativeImageDescriptor.identifier(input["generation"])
        if let binding {
          binding.release(resourceId: resource, generation: generation, result: result)
        } else {
          result(["released": true])
        }
      case "clear":
        guard let binding else {
          result(["cleared": true])
          return
        }
        binding.clear { error in
          if let error {
            result(error.flutterError)
          } else {
            self.bindings.removeValue(forKey: id)
            result(["cleared": true])
          }
        }
      default: result(FlutterMethodNotImplemented)
      }
    } catch let error as NativeImageFailure { result(error.flutterError) } catch {
      result(
        NativeImageFailure(code: "runtime_lost", message: "Native image storage is unavailable")
          .flutterError)
    }
  }

  @available(iOS 14.5, *)
  private func bind(_ input: [String: Any], result: @escaping FlutterResult) throws {
    let token = try NativeImageDescriptor.identifier(input["token"])
    guard let text = input["origin"] as? String, let url = URL(string: text),
      let origin = Self.httpsOrigin(url), origin == text,
      url.path.isEmpty, url.query == nil, url.fragment == nil
    else {
      throw NativeImageFailure(
        code: "protocol_error", message: "Image binding requires an HTTPS origin")
    }
    let parameters = try JSONSerialization.data(withJSONObject: [origin, token])
    guard let json = String(data: parameters, encoding: .utf8) else {
      throw NativeImageFailure.lost
    }
    let script = """
      (() => { const expected = \(json);
        return window === window.top && location.origin === expected[0] &&
          ['/runtime/host','/runtime/host.html'].includes(location.pathname) &&
          !location.search && !location.hash && window.__karuyomiNativeImageToken === expected[1];
      })()
      """
    let candidates = candidateWebViews().filter { Self.isControlPage($0.url, origin: origin) }
    let attempt = NativeImageBindAttempt(result: result)
    pendingBindings[attempt.id] = attempt
    let deadline = DispatchWorkItem { [weak self, weak attempt] in
      guard let self, let attempt else { return }
      self.finishBinding(attempt, value: NativeImageFailure.lost.flutterError)
    }
    attempt.deadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + bindingGrace, execute: deadline)
    let group = DispatchGroup()
    for view in candidates {
      group.enter()
      view.evaluateJavaScript(script) { [weak self, weak view] value, error in
        if let self, self.pendingBindings[attempt.id] === attempt,
          let view, error == nil, value as? Bool == true
        {
          attempt.matches.append(view)
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { [weak self] in
      guard let self, !self.detached, self.pendingBindings[attempt.id] === attempt else {
        return
      }
      guard attempt.matches.count == 1, let view = attempt.matches.first else {
        self.finishBinding(
          attempt,
          value:
            NativeImageFailure(
              code: "unsupported_capability",
              message: "The managed runtime WebView could not be uniquely bound"
            ).flutterError)
        return
      }
      if let entry = self.bindings.first(where: {
        $0.value.webView === view && $0.value.token == token && !$0.value.closed
      }) {
        self.finishBinding(
          attempt,
          value: ["bindingId": entry.key, "directoryUrl": entry.value.directory.absoluteString])
        return
      }
      do {
        let directory = try self.storageDirectory().appendingPathComponent(
          UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try Self.checkDirectory(directory)
        let id = UUID().uuidString
        let binding = NativeImageBinding(
          webView: view, origin: origin, token: token, directory: directory, budget: self.budget,
          onDrained: { [weak self = self] in self?.bindings.removeValue(forKey: id) })
        self.bindings[id] = binding
        self.finishBinding(
          attempt, value: ["bindingId": id, "directoryUrl": directory.absoluteString])
      } catch {
        self.finishBinding(
          attempt,
          value:
            NativeImageFailure(
              code: "runtime_lost", message: "Native image directory creation failed"
            ).flutterError)
      }
    }
  }

  private func finishBinding(_ attempt: NativeImageBindAttempt, value: Any?) {
    guard pendingBindings.removeValue(forKey: attempt.id) === attempt else { return }
    attempt.deadline?.cancel()
    attempt.deadline = nil
    attempt.matches.removeAll()
    let result = attempt.result
    attempt.result = nil
    result?(value)
  }

  func invalidate() {
    detached = true
    for attempt in Array(pendingBindings.values) {
      finishBinding(attempt, value: NativeImageFailure.lost.flutterError)
    }
    for binding in Array(bindings.values) { binding.clear { _ in } }
    bindings.removeAll()
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) { invalidate() }
}

private final class NativeImageBindAttempt {
  let id = UUID()
  var matches: [WKWebView] = []
  var result: FlutterResult?
  var deadline: DispatchWorkItem?

  init(result: @escaping FlutterResult) { self.result = result }
}

/// The native transfer operations used by this image lifecycle. WKDownload
/// conforms directly; tests can defer its callbacks without constructing WebKit
/// objects whose public initializer has no actual download backing it.
@available(iOS 14.5, *)
protocol NativeImageDownload: AnyObject {
  var delegate: (any WKDownloadDelegate)? { get set }
  var progress: Progress { get }
  func cancel(_ completionHandler: (@MainActor @Sendable (Data?) -> Void)?)
}

@available(iOS 14.5, *)
extension WKDownload: NativeImageDownload {}

@available(iOS 14.5, *)
typealias NativeImageDownloadStarter = (
  WKWebView, URLRequest, @escaping (any NativeImageDownload) -> Void
) -> Void

@available(iOS 14.5, *)
private final class NativeImageJob {
  let descriptor: NativeImageDescriptor
  let file: URL
  var acquisition: FlutterResult?
  var download: (any NativeImageDownload)?
  var progress: NSKeyValueObservation?
  var cancelling: NativeImageFailure?
  var cancellationStarted = false
  var cancellationExpired = false
  var cancellationDeadline: DispatchWorkItem?
  // WKDownload.webView is weak. Keep the originating container alive until WebKit
  // has delivered and stopped the transfer, including a late start callback.
  var originatingWebView: WKWebView?
  var stopped = false
  var published = false
  var waiters: [(NativeImageFailure?) -> Void] = []

  init(
    _ descriptor: NativeImageDescriptor, file: URL, webView: WKWebView,
    result: @escaping FlutterResult
  ) {
    self.descriptor = descriptor
    self.file = file
    originatingWebView = webView
    acquisition = result
  }
}

@available(iOS 14.5, *)
final class NativeImageBinding: NSObject, WKDownloadDelegate {
  weak var webView: WKWebView?
  let origin: String
  let token: String
  let directory: URL
  let budget: NativeImageBudget
  private let cancellationGrace: TimeInterval
  private let startDownload: NativeImageDownloadStarter
  private let onDrained: (() -> Void)?
  private var drainageReported = false
  private(set) var closed = false
  private var jobs: [String: NativeImageJob] = [:]
  private var downloads: [ObjectIdentifier: NativeImageJob] = [:]

  init(
    webView: WKWebView, origin: String, token: String, directory: URL, budget: NativeImageBudget,
    cancellationGrace: TimeInterval = 1,
    startDownload: @escaping NativeImageDownloadStarter = { view, request, completion in
      view.startDownload(using: request) { completion($0) }
    }, onDrained: (() -> Void)? = nil
  ) {
    self.webView = webView
    self.origin = origin
    self.token = token
    self.directory = directory
    self.budget = budget
    self.cancellationGrace = cancellationGrace
    self.startDownload = startDownload
    self.onDrained = onDrained
  }

  func acquire(_ descriptor: NativeImageDescriptor, result: @escaping FlutterResult) {
    do {
      guard !closed, let webView, NativeImageFiles.isControlPage(webView.url, origin: origin) else {
        throw NativeImageFailure.lost
      }
      guard jobs[descriptor.key] == nil,
        !jobs.values.contains(where: {
          $0.descriptor.requestId == descriptor.requestId
            && $0.descriptor.generation == descriptor.generation
        })
      else { throw NativeImageFailure(code: "protocol_error", message: "Duplicate image transfer") }
      try NativeImageFiles.checkDirectory(directory)
      try budget.reserve(descriptor)
      let job = NativeImageJob(
        descriptor, file: directory.appendingPathComponent(UUID().uuidString + ".image"),
        webView: webView,
        result: result)
      jobs[descriptor.key] = job
      startDownload(webView, URLRequest(url: descriptor.url)) { [self, job] download in
        guard self.jobs[job.descriptor.key] === job, job.download == nil,
          !job.published, !job.stopped
        else {
          download.cancel { _ in }
          return
        }
        job.download = download
        guard !self.closed, job.cancelling == nil, !job.cancellationExpired else {
          job.cancelling = job.cancelling ?? .lost
          self.cancelDownload(job)
          return
        }
        self.downloads[ObjectIdentifier(download)] = job
        download.delegate = self
        job.progress = download.progress.observe(\.completedUnitCount, options: [.new]) {
          [weak self, weak job] progress, _ in
          let count = progress.completedUnitCount
          DispatchQueue.main.async {
            guard let self, let job, count > job.descriptor.byteLength else { return }
            self.stop(
              job,
              reason: NativeImageFailure(
                code: "limit_exceeded", message: "Downloaded image exceeded its reserved size")
            ) { _ in }
          }
        }
      }
    } catch let error as NativeImageFailure { result(error.flutterError) } catch {
      result(NativeImageFailure.lost.flutterError)
    }
  }

  func cancel(requestId: String, generation: String, result: @escaping FlutterResult) {
    guard
      let job = jobs.values.first(where: {
        !$0.published && $0.descriptor.requestId == requestId
          && $0.descriptor.generation == generation
      })
    else {
      result(["released": true])
      return
    }
    stop(job, reason: .cancelled) { error in
      if let error { result(error.flutterError) } else { result(["released": true]) }
    }
  }

  func release(resourceId: String, generation: String, result: @escaping FlutterResult) {
    guard let job = jobs[generation + "\0" + resourceId] else {
      result(["released": true])
      return
    }
    stop(job, reason: .cancelled) { error in
      if let error { result(error.flutterError) } else { result(["released": true]) }
    }
  }

  func clear(completion: @escaping (NativeImageFailure?) -> Void) {
    closed = true
    let group = DispatchGroup()
    var failure: NativeImageFailure?
    for job in Array(jobs.values) {
      group.enter()
      stop(job, reason: .lost) { error in
        if let error { failure = error }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      if let failure {
        completion(failure)
        return
      }
      completion(self.drainIfClosed())
    }
  }

  private func drainIfClosed() -> NativeImageFailure? {
    guard closed, jobs.isEmpty else { return nil }
    do {
      if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
      }
      if !drainageReported {
        drainageReported = true
        onDrained?()
      }
      return nil
    } catch {
      return NativeImageFailure(
        code: "runtime_lost", message: "Native image directory cleanup failed")
    }
  }

  private func stop(
    _ job: NativeImageJob, reason: NativeImageFailure,
    completion: @escaping (NativeImageFailure?) -> Void
  ) {
    guard jobs[job.descriptor.key] === job else {
      completion(nil)
      return
    }
    job.waiters.append(completion)
    job.cancelling = job.cancelling ?? reason
    if job.published || job.stopped {
      finish(job, failure: job.cancelling)
      return
    }
    if job.cancellationExpired {
      rejectCancellationWaiters(job)
      return
    }
    if job.cancellationDeadline == nil {
      let deadline = DispatchWorkItem { [weak self, weak job] in
        guard let self, let job, self.jobs[job.descriptor.key] === job, !job.stopped else {
          return
        }
        // There is no public cancel handle before startDownload's callback, and
        // WKDownload.cancel itself is asynchronous. A deadline can report loss,
        // never successful cancellation or reclaimed quota. Retain the tombstone
        // and originating WebView until a real cancellation callback arrives.
        job.cancellationExpired = true
        self.closed = true
        self.rejectCancellationWaiters(job)
        for other in Array(self.jobs.values) where other !== job && !other.published {
          self.stop(other, reason: .lost) { _ in }
        }
      }
      job.cancellationDeadline = deadline
      DispatchQueue.main.asyncAfter(deadline: .now() + cancellationGrace, execute: deadline)
    }
    cancelDownload(job)
  }

  private func rejectCancellationWaiters(_ job: NativeImageJob) {
    let acquisition = job.acquisition
    job.acquisition = nil
    acquisition?(NativeImageFailure.lost.flutterError)
    let waiters = job.waiters
    job.waiters = []
    for waiter in waiters { waiter(.lost) }
  }

  private func cancelDownload(_ job: NativeImageJob) {
    guard let download = job.download, !job.cancellationStarted else { return }
    job.cancellationStarted = true
    download.cancel { _ in self.finish(job, failure: job.cancelling) }
  }

  private func finish(_ job: NativeImageJob, failure: NativeImageFailure?) {
    guard jobs[job.descriptor.key] === job else { return }
    job.stopped = true
    job.cancellationDeadline?.cancel()
    job.cancellationDeadline = nil
    job.originatingWebView = nil
    job.progress = nil
    do {
      if FileManager.default.fileExists(atPath: job.file.path) {
        try FileManager.default.removeItem(at: job.file)
      }
    } catch {
      let cleanup = NativeImageFailure(
        code: "runtime_lost", message: "Native image file cleanup failed")
      let acquisition = job.acquisition
      job.acquisition = nil
      acquisition?(cleanup.flutterError)
      let waiters = job.waiters
      job.waiters = []
      for waiter in waiters { waiter(cleanup) }
      return
    }
    jobs.removeValue(forKey: job.descriptor.key)
    if let download = job.download { downloads.removeValue(forKey: ObjectIdentifier(download)) }
    job.download?.delegate = nil
    budget.release(job.descriptor)
    let drainageFailure = drainIfClosed()
    let acquisition = job.acquisition
    job.acquisition = nil
    acquisition?((failure ?? NativeImageFailure.lost).flutterError)
    let waiters = job.waiters
    job.waiters = []
    for waiter in waiters { waiter(drainageFailure) }
  }

  func download(
    _ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    guard let job = downloads[ObjectIdentifier(download)], !closed, job.cancelling == nil else {
      completionHandler(nil)
      return
    }
    guard response.url == job.descriptor.url,
      response.expectedContentLength == job.descriptor.byteLength
    else {
      completionHandler(nil)
      stop(
        job,
        reason: NativeImageFailure(
          code: "integrity_error", message: "Blob transfer metadata changed")
      ) { _ in }
      return
    }
    completionHandler(job.file)
  }

  func downloadDidFinish(_ download: WKDownload) {
    guard let job = downloads[ObjectIdentifier(download)] else { return }
    // A cancel ACK comes from WKDownload.cancel, never from an earlier delegate event.
    if job.cancelling != nil { return }
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: job.file.path)
      guard attributes[.type] as? FileAttributeType == .typeRegular,
        (attributes[.size] as? NSNumber)?.intValue == job.descriptor.byteLength
      else {
        throw NativeImageFailure(
          code: "integrity_error",
          message: "Managed image file length does not match its descriptor")
      }
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: job.file.path)
      job.progress = nil
      job.published = true
      job.originatingWebView = nil
      job.download?.delegate = nil
      downloads.removeValue(forKey: ObjectIdentifier(download))
      job.download = nil
      let result = job.acquisition
      job.acquisition = nil
      result?(["url": job.file.absoluteString])
    } catch let error as NativeImageFailure { finish(job, failure: error) } catch {
      finish(job, failure: .lost)
    }
  }

  func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
    guard let job = downloads[ObjectIdentifier(download)], job.cancelling == nil else { return }
    finish(
      job,
      failure: NativeImageFailure(code: "source_error", message: "Managed image download failed"))
  }

  func download(
    _ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
  ) {
    decisionHandler(.cancel)
  }

  func download(
    _ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(.cancelAuthenticationChallenge, nil)
  }
}
