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
        // TODO(milestone 1): once evaluation exists, this test should
        // instantiate Counter, call increment(), and assert count == 1.
        // That's the real target for "interpreter core" — parsing alone
        // is not the milestone, evaluation is.
    }
}
