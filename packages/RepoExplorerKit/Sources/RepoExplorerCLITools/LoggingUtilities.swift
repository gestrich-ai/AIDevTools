import Foundation

// MARK: - Logging Utilities

public func printStep(_ message: String) {
    print("")
    let circleSymbol = "\u{25EF}"
    print("\(circleSymbol) \(message)")
}

public func printSuccess(_ message: String) {
    print("")
    let checkmarkSymbol = "\u{2705}"
    print("\(checkmarkSymbol) \(message)")
    print("")
}

public func printError(_ message: String) {
    print("")
    let errorSymbol = "\u{274C}"
    print("\(errorSymbol) \(message)")
    print("")
}

public func printWarning(_ message: String) {
    print("")
    let warningSymbol = "\u{26A0}"
    print("\(warningSymbol) \(message)")
    print("")
}
