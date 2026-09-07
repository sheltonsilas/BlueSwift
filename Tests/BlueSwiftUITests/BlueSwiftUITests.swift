import XCTest
@testable import BlueSwiftUI
import BlueSwiftCore

final class BlueSwiftUITests: XCTestCase {
    func testClassDiagramViewBuildsFromCoreDefinitions() {
        let definitions = [
            ClassDefinition(
                kind: .class,
                name: "A",
                superclassName: nil,
                properties: [.init(name: "x", typeName: "Int", defaultExpression: "0")],
                methods: ["do": .init(name: "do", parameterNames: [], statements: [])],
                initializers: []
            ),
            ClassDefinition(
                kind: .class,
                name: "B",
                superclassName: "A",
                properties: [],
                methods: ["run": .init(name: "run", parameterNames: [], statements: [])],
                initializers: []
            )
        ]

        let _ = ClassDiagramView(definitions: definitions)
        XCTAssertTrue(true)
    }

    func testWorkspaceParsesAndRunsMethod() {
        var workspace = BlueSwiftWorkspace(source: """
        class Counter {
            var count: Int = 0
            func increment() -> Int {
                count += 1
                return count
            }
        }
        """)

        XCTAssertTrue(workspace.parseSource())
        XCTAssertTrue(workspace.run(classNamed: "Counter", methodNamed: "increment"))
        XCTAssertEqual(workspace.lastResult, .int(1))
        XCTAssertEqual(workspace.lastProperties["count"], .int(1))
        XCTAssertNil(workspace.lastError)
    }

    func testWorkspaceSaveAndLoadRoundTrip() throws {
        var workspace = BlueSwiftWorkspace(source: "class Sample { var x: Int = 1 }")
        XCTAssertTrue(workspace.parseSource())

        let tempURL = URL(fileURLWithPath: "/tmp/blueswiftui-workspace-test.json")
        try? FileManager.default.removeItem(at: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        try workspace.save(to: tempURL)

        var loaded = BlueSwiftWorkspace()
        try loaded.load(from: tempURL)

        XCTAssertEqual(loaded.source, workspace.source)
        XCTAssertEqual(loaded.definitions.map(\.name), ["Sample"])
    }
}
