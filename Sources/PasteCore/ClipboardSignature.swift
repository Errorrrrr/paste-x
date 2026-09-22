import CryptoKit
import Foundation

public enum ClipboardSignature {
    public static func make(kind: ClipboardKind, payloads: [ClipboardPayload]) -> String {
        var signatureInput = Data()
        append(kind.rawValue, to: &signatureInput)

        let hasMultipleItems = payloads.contains { $0.itemIndex != 0 }
        for payload in payloads.sorted(by: {
            $0.itemIndex == $1.itemIndex ? $0.typeIdentifier < $1.typeIdentifier : $0.itemIndex < $1.itemIndex
        }) {
            if hasMultipleItems { append(String(payload.itemIndex), to: &signatureInput) }
            append(payload.typeIdentifier, to: &signatureInput)
            signatureInput.append(payload.data)
            signatureInput.append(0)
        }

        let digest = SHA256.hash(data: signatureInput)
        return "\(kind.rawValue):\(digest.map { String(format: "%02x", $0) }.joined())"
    }

    private static func append(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
        data.append(0)
    }
}
