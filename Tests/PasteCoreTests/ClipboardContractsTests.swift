import Foundation
import Testing
@testable import PasteCore

@Test func signatureIsStableAcrossPayloadOrdering() throws {
    let first = ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))
    let second = ClipboardPayload(typeIdentifier: "public.url", data: Data("https://example.com".utf8))

    let signatureA = ClipboardSignature.make(kind: .url, payloads: [first, second])
    let signatureB = ClipboardSignature.make(kind: .url, payloads: [second, first])

    #expect(signatureA == signatureB)
    #expect(signatureA.hasPrefix("url:"))
}

@Test func clipboardItemCarriesSharedRenderableAndPasteData() throws {
    let createdAt = Date(timeIntervalSince1970: 1_777_777_777)
    let payload = ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))
    let item = ClipboardItem(
        kind: .text,
        summary: "hello",
        createdAt: createdAt,
        signature: ClipboardSignature.make(kind: .text, payloads: [payload]),
        payloads: [payload]
    )

    #expect(item.kind == .text)
    #expect(item.summary == "hello")
    #expect(item.createdAt == createdAt)
    #expect(item.payloads == [payload])
}

@Test func systemCapabilityProtocolsAreMockableByParallelTasks() async throws {
    let item = ClipboardItem(
        kind: .text,
        summary: "hello",
        createdAt: Date(timeIntervalSince1970: 1),
        signature: "text:mock",
        payloads: [ClipboardPayload(typeIdentifier: "public.utf8-plain-text", data: Data("hello".utf8))]
    )
    let target = PasteTarget(
        bundleIdentifier: "com.apple.TextEdit",
        processIdentifier: 42,
        capturedAt: Date(timeIntervalSince1970: 2)
    )
    let coordinator = MockPasteCoordinator(result: .copiedOnly(reason: .accessibilityNotTrusted))

    let result = await coordinator.paste(item, to: target)

    #expect(result == .copiedOnly(reason: .accessibilityNotTrusted))
    #expect(coordinator.lastItem == item)
    #expect(coordinator.lastTarget == target)
}

private final class MockPasteCoordinator: PasteCoordinating {
    let result: PasteResult
    private(set) var lastItem: ClipboardItem?
    private(set) var lastTarget: PasteTarget?

    init(result: PasteResult) {
        self.result = result
    }

    func paste(_ item: ClipboardItem, to target: PasteTarget?) async -> PasteResult {
        lastItem = item
        lastTarget = target
        return result
    }
}
