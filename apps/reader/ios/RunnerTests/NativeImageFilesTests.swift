import Flutter
import Foundation
import WebKit
import XCTest

@testable import Runner

final class NativeImageFilesTests: XCTestCase {
  private let origin = "https://reader.example"

  private func input(bytes: Int = 100) -> [String: Any] {
    [
      "requestId": "request", "resourceId": "resource", "generation": "generation",
      "url": "blob:https://reader.example/00000000-0000-0000-0000-000000000001",
      "byteLength": bytes,
    ]
  }

  func testOnlyHTTPSControlDocumentsCanBeBound() {
    XCTAssertTrue(
      NativeImageFiles.isControlPage(URL(string: origin + "/runtime/host"), origin: origin))
    XCTAssertTrue(
      NativeImageFiles.isControlPage(URL(string: origin + "/runtime/host.html"), origin: origin))
    for text in [
      "http://reader.example/runtime/host", "https://other.example/runtime/host",
      origin + "/runtime/host?query", origin + "/runtime/host#fragment",
      origin + "/runtime/host/", origin + "/browse",
      origin + "/runtime/%68ost", origin + "/runtime%2Fhost",
      "https://user@reader.example/runtime/host",
    ] {
      XCTAssertFalse(NativeImageFiles.isControlPage(URL(string: text), origin: origin), text)
    }
    XCTAssertEqual(
      NativeImageFiles.httpsOrigin(URL(string: "https://reader.example:443/path")), origin)
    XCTAssertEqual(
      NativeImageFiles.httpsOrigin(URL(string: "https://reader.example:444/path")), origin + ":444")
  }

  func testDescriptorsRejectRemoteURLsAndMalformedScalarMetadata() throws {
    let valid = try NativeImageDescriptor(input(), origin: origin)
    XCTAssertEqual(valid.byteLength, 100)
    for value in [
      "https://reader.example/image.png", "file:///tmp/image.png",
      "blob:https://other.example/image", "blob:null/image",
      "blob:https://reader.example/image?query", "blob:https://reader.example/image#fragment",
    ] {
      var metadata = input()
      metadata["url"] = value
      XCTAssertThrowsError(try NativeImageDescriptor(metadata, origin: origin), value)
    }
    for field in ["byteLength"] {
      for scalar: Any in [true, 1.5, 0, -1, "100"] {
        var metadata = input()
        metadata[field] = scalar
        XCTAssertThrowsError(try NativeImageDescriptor(metadata, origin: origin), field)
      }
    }
    var metadata = input()
    metadata["resourceId"] = String(repeating: "x", count: 201)
    XCTAssertThrowsError(try NativeImageDescriptor(metadata, origin: origin))
    for field in ["requestId", "resourceId", "generation"] {
      for value in ["joined\0identity", "line\nidentity"] {
        metadata = input()
        metadata[field] = value
        XCTAssertThrowsError(try NativeImageDescriptor(metadata, origin: origin), field)
      }
    }
    XCTAssertThrowsError(
      try NativeImageDescriptor(input(bytes: 64 * 1024 * 1024 + 1), origin: origin))
  }

  func testByteAndResourceReservationsAreSharedAndSurviveFailedReservations() throws {
    let budget = NativeImageBudget()
    let full = try NativeImageDescriptor(input(bytes: 64 * 1024 * 1024), origin: origin)
    let small = try NativeImageDescriptor(input(), origin: origin)
    try budget.reserve(full)
    XCTAssertThrowsError(try budget.reserve(small))
    XCTAssertEqual(budget.resources, 1)
    XCTAssertEqual(budget.bytes, 64 * 1024 * 1024)
    budget.release(full)
    for _ in 0..<6 { try budget.reserve(small) }
    XCTAssertThrowsError(try budget.reserve(small))
    XCTAssertEqual(budget.resources, 6)
    for _ in 0..<6 { budget.release(small) }
    XCTAssertEqual(budget.resources, 0)
    XCTAssertEqual(budget.bytes, 0)
  }

  func testEncodedTransferNeedsNoImageMetadata() throws {
    let image = try NativeImageDescriptor(input(), origin: origin)
    XCTAssertEqual(image.byteLength, 100)
    let budget = NativeImageBudget()
    try budget.reserve(image)
    XCTAssertEqual(budget.bytes, 100)
    budget.release(image)
    XCTAssertEqual(budget.bytes, 0)
  }

  func testManagedDirectoryMustBeARealDirectory() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let link = root.appendingPathComponent("link")
    try manager.createSymbolicLink(at: link, withDestinationURL: root)
    XCTAssertNoThrow(try NativeImageFiles.checkDirectory(root))
    XCTAssertThrowsError(try NativeImageFiles.checkDirectory(link))
    let file = root.appendingPathComponent("plain")
    try Data([1]).write(to: file)
    XCTAssertThrowsError(try NativeImageFiles.checkDirectory(file))
  }

  func testExpiredHandlesAreIdempotentAndCannotCreateResources() {
    let bridge = NativeImageFiles()
    for method in ["cancel", "release", "clear"] {
      var returned = false
      bridge.handle(
        FlutterMethodCall(
          methodName: method,
          arguments: [
            "bindingId": "expired", "requestId": "request", "resourceId": "resource",
            "generation": "old",
          ])
      ) { result in
        returned = true
        XCTAssertEqual(
          (result as? [String: Bool])?[method == "clear" ? "cleared" : "released"], true)
      }
      XCTAssertTrue(returned)
    }
    var error: FlutterError?
    bridge.handle(FlutterMethodCall(methodName: "acquire", arguments: ["bindingId": "expired"])) {
      error = $0 as? FlutterError
    }
    XCTAssertEqual(error?.code, "runtime_lost")
  }

  @MainActor
  func testClearBeforeStartWaitsForActualCancellation() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let view = DeferredImageWebView(frame: .zero)
    let starter = DeferredImageStart()
    let budget = NativeImageBudget()
    let binding = NativeImageBinding(
      webView: view, origin: origin, token: "token", directory: root, budget: budget,
      cancellationGrace: 1, startDownload: starter.start)
    let acquired = expectation(description: "acquire cancelled")
    binding.acquire(try NativeImageDescriptor(input(), origin: origin)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
      acquired.fulfill()
    }
    let cleared = expectation(description: "clear after real cancel")
    var clearFinished = false
    binding.clear { failure in
      XCTAssertNil(failure)
      clearFinished = true
      cleared.fulfill()
    }
    XCTAssertFalse(clearFinished)
    XCTAssertEqual(budget.resources, 1)
    let download = DeferredImageDownload()
    starter.completeStart(download)
    XCTAssertEqual(download.cancellations, 1)
    XCTAssertNil(download.delegate)
    XCTAssertFalse(clearFinished)
    XCTAssertEqual(budget.resources, 1)
    download.completeCancellation()
    wait(for: [acquired, cleared], timeout: 1)
    XCTAssertEqual(budget.resources, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  @MainActor
  func testPendingStartDeadlineRetainsContainerAndQuotaUntilLateCancelAcknowledgement() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    weak var retainedView: DeferredImageWebView?
    let budget = NativeImageBudget()
    let starter = DeferredImageStart()
    var drained = 0
    let acquired = expectation(description: "acquire reports container loss")
    var acquireResults = 0
    let binding: NativeImageBinding
    let completeStart: ((any NativeImageDownload) -> Void)?
    do {
      let startingView = DeferredImageWebView(frame: .zero)
      retainedView = startingView
      binding = NativeImageBinding(
        webView: startingView, origin: origin, token: "token", directory: root, budget: budget,
        cancellationGrace: 0.01, startDownload: starter.start, onDrained: { drained += 1 })
      binding.acquire(try NativeImageDescriptor(input(), origin: origin)) { value in
        acquireResults += 1
        XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
        acquired.fulfill()
      }
      completeStart = starter.takeStartCompletion()
    }
    let timedOut = expectation(description: "clear fails without a cancel handle")
    binding.clear { failure in
      XCTAssertEqual(failure?.code, "runtime_lost")
      timedOut.fulfill()
    }
    wait(for: [acquired, timedOut], timeout: 1)
    XCTAssertNotNil(retainedView)
    XCTAssertEqual(budget.resources, 1)
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
    XCTAssertEqual(drained, 0)
    let download = DeferredImageDownload()
    completeStart?(download)
    XCTAssertEqual(download.cancellations, 1)
    XCTAssertNil(download.delegate)
    XCTAssertEqual(budget.resources, 1)
    download.completeCancellation()
    XCTAssertEqual(budget.resources, 0)
    XCTAssertEqual(drained, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    XCTAssertEqual(acquireResults, 1)
    let cleared = expectation(description: "clear can retry after tombstone drains")
    binding.clear { failure in
      XCTAssertNil(failure)
      cleared.fulfill()
    }
    wait(for: [cleared], timeout: 1)
    XCTAssertEqual(drained, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
  }

  @MainActor
  func testCancellationDeadlineDoesNotReleaseQuotaBeforeDownloadStops() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let view = DeferredImageWebView(frame: .zero)
    let starter = DeferredImageStart()
    let budget = NativeImageBudget()
    let binding = NativeImageBinding(
      webView: view, origin: origin, token: "token", directory: root, budget: budget,
      cancellationGrace: 0.01, startDownload: starter.start)
    let acquired = expectation(description: "acquire reports cancellation timeout")
    binding.acquire(try NativeImageDescriptor(input(), origin: origin)) { value in
      XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
      acquired.fulfill()
    }
    let download = DeferredImageDownload()
    starter.completeStart(download)
    let cancelled = expectation(description: "cancel fails without actual stop")
    binding.cancel(requestId: "request", generation: "generation") { value in
      XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
      cancelled.fulfill()
    }
    wait(for: [acquired, cancelled], timeout: 1)
    XCTAssertTrue(binding.closed)
    XCTAssertEqual(download.cancellations, 1)
    XCTAssertEqual(budget.resources, 1)
    download.completeCancellation()
    XCTAssertEqual(budget.resources, 0)
  }

  @MainActor
  func testBindDeadlineDiscardsLateEvaluationWithoutCreatingStorage() {
    let first = DeferredBindingWebView(frame: .zero)
    let late = DeferredBindingWebView(frame: .zero)
    var storageRequests = 0
    let bridge = NativeImageFiles(
      bindingGrace: 0.01, candidateWebViews: { [first, late] },
      storageDirectory: {
        storageRequests += 1
        throw NativeImageFailure.lost
      })
    let expired = expectation(description: "bind fails when one evaluation never returns")
    var results = 0
    bridge.handle(
      FlutterMethodCall(methodName: "bind", arguments: ["token": "token", "origin": origin])
    ) { value in
      results += 1
      XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
      expired.fulfill()
    }
    first.completeEvaluation()
    wait(for: [expired], timeout: 1)
    XCTAssertEqual(storageRequests, 0)
    late.completeEvaluation()
    let settled = expectation(description: "late group notification is fenced")
    DispatchQueue.main.async {
      XCTAssertEqual(results, 1)
      XCTAssertEqual(storageRequests, 0)
      settled.fulfill()
    }
    wait(for: [settled], timeout: 1)
  }

  @MainActor
  func testInvalidationDiscardsPendingBindAndItsLateEvaluation() {
    let view = DeferredBindingWebView(frame: .zero)
    var storageRequests = 0
    let bridge = NativeImageFiles(
      bindingGrace: 1, candidateWebViews: { [view] },
      storageDirectory: {
        storageRequests += 1
        throw NativeImageFailure.lost
      })
    var results = 0
    bridge.handle(
      FlutterMethodCall(methodName: "bind", arguments: ["token": "token", "origin": origin])
    ) { value in
      results += 1
      XCTAssertEqual((value as? FlutterError)?.code, "runtime_lost")
    }
    bridge.invalidate()
    XCTAssertEqual(results, 1)
    view.completeEvaluation()
    let settled = expectation(description: "invalidated bind cannot create storage")
    DispatchQueue.main.async {
      XCTAssertEqual(results, 1)
      XCTAssertEqual(storageRequests, 0)
      settled.fulfill()
    }
    wait(for: [settled], timeout: 1)
  }

  private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    return directory
  }
}

@MainActor
private final class DeferredImageWebView: WKWebView {
  override var url: URL? { URL(string: "https://reader.example/runtime/host") }
}

@MainActor
private final class DeferredBindingWebView: WKWebView {
  private var completion: (@MainActor @Sendable (Any?, (any Error)?) -> Void)?
  override var url: URL? { URL(string: "https://reader.example/runtime/host") }

  override func evaluateJavaScript(
    _ javaScriptString: String,
    completionHandler: (@MainActor @Sendable (Any?, (any Error)?) -> Void)? = nil
  ) {
    completion = completionHandler
  }

  func completeEvaluation() {
    let pending = completion
    completion = nil
    pending?(true, nil)
  }
}

private final class DeferredImageStart {
  private var completion: ((any NativeImageDownload) -> Void)?

  func start(
    _ view: WKWebView, _ request: URLRequest,
    completionHandler: @escaping (any NativeImageDownload) -> Void
  ) {
    completion = completionHandler
  }

  func takeStartCompletion() -> ((any NativeImageDownload) -> Void)? {
    let pending = completion
    completion = nil
    return pending
  }

  func completeStart(_ download: any NativeImageDownload) { takeStartCompletion()?(download) }
}

private final class DeferredImageDownload: NativeImageDownload {
  private let controlledProgress = Progress(totalUnitCount: 100)
  weak var delegate: (any WKDownloadDelegate)?
  private var completion: (@MainActor @Sendable (Data?) -> Void)?
  private(set) var cancellations = 0
  var progress: Progress { controlledProgress }

  func cancel(_ completionHandler: (@MainActor @Sendable (Data?) -> Void)? = nil) {
    cancellations += 1
    completion = completionHandler
  }

  @MainActor
  func completeCancellation() {
    let pending = completion
    completion = nil
    pending?(nil)
  }
}
