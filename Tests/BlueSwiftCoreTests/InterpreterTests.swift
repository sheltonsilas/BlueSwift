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
}
