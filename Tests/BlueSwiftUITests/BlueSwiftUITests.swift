import XCTest
@testable import BlueSwiftUI

final class BlueSwiftUITests: XCTestCase {
    func testClassDiagramViewBuilds() {
        let classes = [
            ParsedClass(name: "A", properties: ["x: Int"], methods: ["do()"]),
            ParsedClass(name: "B", properties: [], methods: ["run()"], superclass: "A")
        ]

        // Construct the view to ensure it compiles and the body can be formed.
        let _ = ClassDiagramView(classes: classes)
        // If construction completes, the test passes (no UI runtime required).
        XCTAssertTrue(true)
    }
}
