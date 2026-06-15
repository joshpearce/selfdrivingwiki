import Foundation

/// Dependency-free ULID generator.
///
/// A ULID is a 128-bit value: a 48-bit big-endian millisecond Unix timestamp
/// followed by 80 random bits, rendered as 26 Crockford base32 characters.
/// Because the timestamp is the high-order component and base32 is encoded
/// most-significant-first, ULIDs sort **lexicographically in creation order** —
/// the property we lean on for `PageID` ordering and future date views.
public enum ULID {
    /// Crockford base32 alphabet (no I, L, O, U to avoid ambiguity).
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Generate a new 26-character ULID string.
    /// - Parameter timestamp: the moment to encode; defaults to now. Exposed so
    ///   tests can pin increasing timestamps and assert lexicographic ordering.
    public static func generate(
        at timestamp: Date = Date(),
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let ms = UInt64(max(0, timestamp.timeIntervalSince1970) * 1000)

        // 16 bytes: 6 timestamp (big-endian) + 10 random.
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<6 {
            bytes[i] = UInt8((ms >> (8 * (5 - i))) & 0xFF)
        }
        for i in 6..<16 {
            bytes[i] = UInt8.random(in: 0...255, using: &generator)
        }

        return encodeBase32(bytes)
    }

    /// Convenience overload using the system RNG.
    public static func generate(at timestamp: Date = Date()) -> String {
        var rng = SystemRandomNumberGenerator()
        return generate(at: timestamp, using: &rng)
    }

    /// Encode 16 bytes (128 bits) as 26 Crockford base32 characters. We treat
    /// the bytes as one big integer and peel off 5 bits at a time from the top.
    private static func encodeBase32(_ bytes: [UInt8]) -> String {
        // 128 bits -> 26 chars (130 bits, top 2 bits always 0).
        var bits = 0
        var value = 0
        var out = [Character]()
        out.reserveCapacity(26)

        // Prepend two zero bits so the total is a multiple of 5 (130 bits).
        // Process bytes MSB-first, emitting a char whenever >= 5 bits buffered.
        value = 0
        bits = 2  // two leading pad bits
        for byte in bytes {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                let index = (value >> bits) & 0x1F
                out.append(alphabet[index])
            }
        }
        return String(out)
    }
}
