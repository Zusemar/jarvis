import Foundation

var assertionCount = 0

private func verify(_ result: Bool, _ message: String, file: StaticString, line: UInt) {
    assertionCount += 1
    if !result {
        fputs("FAIL \(file):\(line): \(message)\n", stderr)
        exit(1)
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    verify(actual == expected, "\(message) expected \(expected), got \(actual)", file: file, line: line)
}
func assertNil<T>(_ actual: T?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    verify(actual == nil, "\(message) expected nil, got \(String(describing: actual))", file: file, line: line)
}
func assertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    verify(value, "expected true", file: file, line: line)
}
func assertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); verify(false, "expected an error", file: file, line: line) }
    catch { verify(true, "", file: file, line: line) }
}
