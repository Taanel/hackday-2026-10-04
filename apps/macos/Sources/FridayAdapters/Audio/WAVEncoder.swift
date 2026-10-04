import Foundation

public enum WAVEncoder {
    /// Standard PCM16 mono WAV, accepted by both Hex and Moonshine fixtures.
    public static func encode(_ samples: [Float], sampleRate: UInt32 = 16_000) -> Data {
        let byteCount = UInt32(samples.count * 2)
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        ascii("RIFF"); u32(36 + byteCount); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        ascii("data"); u32(byteCount)
        for sample in samples {
            let clamped = sample.isFinite ? min(1, max(-1, sample)) : 0
            u16(UInt16(bitPattern: Int16((clamped * 32767).rounded())))
        }
        return data
    }
}
