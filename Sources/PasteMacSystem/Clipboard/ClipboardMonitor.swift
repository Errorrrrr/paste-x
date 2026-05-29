import Foundation
import PasteCore

public protocol ClipboardPayloadSource: AnyObject {
    func currentChangeCount() -> Int
    func currentPayloads() -> [ClipboardPayload]
}

public final class ClipboardMonitor: NSObject, ClipboardMonitoring {
    private let source: ClipboardPayloadSource
    private let classifier: ClipboardClassifying
    private let historyStore: ClipboardHistoryProviding
    private let interval: TimeInterval
    private var lastChangeCount: Int
    private var timer: Timer?
    private var pendingSelfWriteSignature: String?

    public init(
        source: ClipboardPayloadSource,
        classifier: ClipboardClassifying,
        historyStore: ClipboardHistoryProviding,
        interval: TimeInterval = 0.5
    ) {
        self.source = source
        self.classifier = classifier
        self.historyStore = historyStore
        self.interval = interval
        self.lastChangeCount = source.currentChangeCount()
        super.init()
    }

    public convenience init(
        classifier: ClipboardClassifying,
        historyStore: ClipboardHistoryProviding,
        interval: TimeInterval = 0.5
    ) {
        self.init(
            source: SystemClipboardPayloadSource(),
            classifier: classifier,
            historyStore: historyStore,
            interval: interval
        )
    }

    public func start() {
        guard timer == nil else { return }

        timer = Timer.scheduledTimer(
            timeInterval: interval,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func markSelfWrite(signature: String) {
        pendingSelfWriteSignature = signature
    }

    public func poll(createdAt: Date = Date()) {
        let changeCount = source.currentChangeCount()
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        guard let item = classifier.makeItem(from: source.currentPayloads(), createdAt: createdAt) else {
            return
        }

        if let pendingSelfWriteSignature {
            self.pendingSelfWriteSignature = nil
            guard item.signature != pendingSelfWriteSignature else {
                return
            }
        }

        historyStore.insert(item)
    }

    @objc private func timerFired() {
        poll()
    }
}
