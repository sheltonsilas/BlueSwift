import XCTest
@testable import BlueSwiftCore

final class InterpreterTests: XCTestCase {

    func testParsesSimpleClass() {
        let source = """
        class Counter {
            var count: Int = 0

            func increment() {
                count += 1
            }
        }
        """

        let interpreter = Interpreter()
        let tree = interpreter.parse(source)

        XCTAssertFalse(tree.description.isEmpty)

        let (_, finalProperties) = interpreter.evaluate(classNamed: "Counter", callingMethod: "increment")
        XCTAssertEqual(finalProperties["count"], .int(1))
    }

    func testAdderReturnsUpdatedTotal() {
        let source = """
        class Adder {
            var total: Int = 1 + 1

            func add(_ value: Int) -> Int {
                self.total += value
                return self.total
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let (result, finalProperties) = interpreter.evaluate(
            classNamed: "Adder",
            callingMethod: "add",
            with: [.int(3)]
        )

        XCTAssertEqual(result, .int(5))
        XCTAssertEqual(finalProperties["total"], .int(5))
    }

    func testInitializerRunsBeforeMethod() {
        let source = """
        class BootCounter {
            var count: Int = 0

            init() {
                count = 4
            }

            func value() -> Int {
                return count
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let (result, finalProperties) = interpreter.evaluate(classNamed: "BootCounter", callingMethod: "value")

        XCTAssertEqual(result, .int(4))
        XCTAssertEqual(finalProperties["count"], .int(4))
    }

    func testWhileAndIfControlFlow() {
        let source = """
        class LoopCounter {
            var total: Int = 0

            func run(_ limit: Int) -> Int {
                var i: Int = 0
                while i < limit {
                    if i < 2 {
                        total += 1
                    } else {
                        total += 2
                    }
                    i += 1
                }
                return total
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let (result, finalProperties) = interpreter.evaluate(classNamed: "LoopCounter", callingMethod: "run", with: [.int(3)])

        XCTAssertEqual(result, .int(4))
        XCTAssertEqual(finalProperties["total"], .int(4))
    }

    func testChildClassReadsInheritedProperty() {
        let source = """
        class Base {
            var count: Int = 7
        }

        class Child: Base {
            func value() -> Int {
                return self.count
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let (result, finalProperties) = interpreter.evaluate(classNamed: "Child", callingMethod: "value")

        XCTAssertEqual(result, .int(7))
        XCTAssertEqual(finalProperties["count"], .int(7))
    }

    func testStructMethodMutatesStoredProperty() {
        let source = """
        struct CounterStruct {
            var count: Int = 0

            mutating func increment() -> Int {
                count += 1
                return count
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)

        let (result, finalProperties) = interpreter.evaluate(classNamed: "CounterStruct", callingMethod: "increment")

        XCTAssertEqual(result, .int(1))
        XCTAssertEqual(finalProperties["count"], .int(1))
    }
}
