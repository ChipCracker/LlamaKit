import XCTest
@testable import LlamaKit

/// Verifies the streaming UTF-8 reassembly used during token-by-token generation:
/// byte-level BPE can split a multi-byte character (emoji, umlauts, CJK, …) over
/// several tokens, so decoding each token in isolation produced `�`. The
/// `splitValidUTF8` byte-buffer must reconstruct the original text exactly.
final class UTF8StreamingTests: XCTestCase {

    /// Feeds arbitrary byte chunks (simulating per-token pieces) through the
    /// splitter + carry-over buffer and returns the reassembled string.
    private func reassemble(_ chunks: [[UInt8]]) -> String {
        var pending: [UInt8] = []
        var out = ""
        for chunk in chunks {
            pending += chunk
            let (text, rest) = LlamaEngine.splitValidUTF8(pending)
            pending = rest
            out += text
        }
        if !pending.isEmpty { out += String(decoding: pending, as: UTF8.self) }
        return out
    }

    func testEmojiSplitByteByByte() {
        // Worst case: every byte arrives as its own "token".
        let s = "Hi 👋🏼 Welt 📍 — ☕️!"
        XCTAssertEqual(reassemble(Array(s.utf8).map { [$0] }), s)
    }

    func testVariousChunkBoundaries() {
        let s = "Smörgåsbord café ☕️, 日本語, 𝕏, 🇩🇪 fertig."
        let bytes = Array(s.utf8)
        for size in [1, 2, 3, 4, 5, 7, 11] {
            var chunks: [[UInt8]] = []
            var i = 0
            while i < bytes.count {
                let e = min(i + size, bytes.count)
                chunks.append(Array(bytes[i..<e])); i = e
            }
            XCTAssertEqual(reassemble(chunks), s, "chunk size \(size)")
        }
    }

    func testAsciiUnaffected() {
        let (text, rest) = LlamaEngine.splitValidUTF8(Array("hello world".utf8))
        XCTAssertEqual(text, "hello world")
        XCTAssertTrue(rest.isEmpty)
    }

    func testIncompleteTailIsHeldBackNotReplaced() {
        // "é" = C3 A9. The lone lead byte must be held back, NOT turned into �.
        let (t1, r1) = LlamaEngine.splitValidUTF8([0xC3])
        XCTAssertEqual(t1, "")
        XCTAssertEqual(r1, [0xC3])
        // Completing the sequence yields the character.
        let (t2, r2) = LlamaEngine.splitValidUTF8([0xC3, 0xA9])
        XCTAssertEqual(t2, "é")
        XCTAssertTrue(r2.isEmpty)
        // A 4-byte emoji missing its last byte is held back entirely.
        let pin = Array("📍".utf8)                 // F0 9F 93 8D
        let (t3, r3) = LlamaEngine.splitValidUTF8(Array(pin.prefix(3)))
        XCTAssertEqual(t3, "")
        XCTAssertEqual(r3, Array(pin.prefix(3)))
    }
}
