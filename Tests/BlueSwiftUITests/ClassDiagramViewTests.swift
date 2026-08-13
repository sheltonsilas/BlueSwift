import XCTest
import BlueSwiftCore
#if canImport(SwiftUI)
import BlueSwiftUI

final class ClassDiagramViewTests: XCTestCase {
    func testClassDiagramViewBuildsForMultipleTypes() throws {
        let source = """
        class Counter {
            var count: Int = 0
            func increment() {
                count += 1
            }
        }

        class Adder {
            var value: Int = 1
            func add(_ amount: Int) -> Int {
                return value + amount
            }
        }

        class SmartAdder: Adder {
            func plusOne() -> Int {
                return add(1)
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        let definitions = try interpreter.resolvedTypeDefinitions()

        XCTAssertNoThrow({
            _ = ClassDiagramView(definitions: definitions)
        }())
    }
}
#endif
