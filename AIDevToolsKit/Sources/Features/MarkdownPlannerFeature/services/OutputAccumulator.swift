import Foundation

/// Thread-safe accumulator for collecting output text
actor OutputAccumulator {
    private var buffer = ""

    var content: String {
        return buffer
    }

    func append(_ text: String) {
        buffer += text
    }
}