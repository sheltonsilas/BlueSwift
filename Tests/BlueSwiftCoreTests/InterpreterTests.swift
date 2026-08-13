import XCTest
@testable import BlueSwiftCore

final class InterpreterTests: XCTestCase {

    func testEvaluatesSimpleIncrementMethod() throws {
        let source = """
        class Counter {
            var count: Int = 0

            func increment() {
                count += 1
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        let evaluation = try interpreter.evaluate(classNamed: "Counter", callingMethod: "increment")

        XCTAssertEqual(evaluation.properties["count"], .int(1))
        XCTAssertEqual(evaluation.value, .void)
    }

    func testEvaluatesMethodWithParameterAndReturnValue() throws {
        let source = """
        class Adder {
            var count: Int = 10

            func add(_ value: Int) -> Int {
                count += value
                return count
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        let evaluation = try interpreter.evaluate(
            classNamed: "Adder",
            callingMethod: "add",
            with: [.int(5)]
        )

        XCTAssertEqual(evaluation.value, .int(15))
        XCTAssertEqual(evaluation.properties["count"], .int(15))
    }
}
