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

    func testEvaluatesIfElseIfElseBranches() throws {
        let source = """
        class Classifier {
            func classify(_ value: Int) -> Int {
                if value < 0 {
                    return -1
                } else if value == 0 {
                    return 0
                } else {
                    return 1
                }
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let negative = try interpreter.evaluate(classNamed: "Classifier", callingMethod: "classify", with: [.int(-2)])
        XCTAssertEqual(negative.value, .int(-1))

        let zero = try interpreter.evaluate(classNamed: "Classifier", callingMethod: "classify", with: [.int(0)])
        XCTAssertEqual(zero.value, .int(0))

        let positive = try interpreter.evaluate(classNamed: "Classifier", callingMethod: "classify", with: [.int(9)])
        XCTAssertEqual(positive.value, .int(1))
    }

    func testEvaluatesWhileLoopAccumulation() throws {
        let source = """
        class Summation {
            func sumTo(_ n: Int) -> Int {
                var total: Int = 0
                var i: Int = 0
                while i < n {
                    total += i
                    i += 1
                }
                return total
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        let evaluation = try interpreter.evaluate(classNamed: "Summation", callingMethod: "sumTo", with: [.int(5)])

        XCTAssertEqual(evaluation.value, .int(10))
    }

    func testEvaluatesForLoopOverRange() throws {
        let source = """
        class RangeSummation {
            func sumRange(_ n: Int) -> Int {
                var total: Int = 0
                for i in 0..<n {
                    total += i
                }
                return total
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        let evaluation = try interpreter.evaluate(classNamed: "RangeSummation", callingMethod: "sumRange", with: [.int(6)])

        XCTAssertEqual(evaluation.value, .int(15))
    }
}
