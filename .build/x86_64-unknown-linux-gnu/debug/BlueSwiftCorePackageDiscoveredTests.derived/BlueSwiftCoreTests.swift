import XCTest
@testable import BlueSwiftCoreTests

fileprivate extension InterpreterTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__InterpreterTests = [
        ("testEvaluatesMethodWithParameterAndReturnValue", testEvaluatesMethodWithParameterAndReturnValue),
        ("testEvaluatesSimpleIncrementMethod", testEvaluatesSimpleIncrementMethod)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __BlueSwiftCoreTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(InterpreterTests.__allTests__InterpreterTests)
    ]
}