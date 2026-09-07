import BlueSwiftCore

#if canImport(SwiftUI)
import SwiftUI

public struct BlueSwiftWorkspaceView: View {
    @State private var workspace: BlueSwiftWorkspace
    @State private var selectedTypeName: String = ""
    @State private var methodName: String = ""
    @State private var argumentText: String = ""

    public init(initialSource: String = Self.defaultSource) {
        _workspace = State(initialValue: BlueSwiftWorkspace(source: initialSource))
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("BlueSwift")
                .font(.largeTitle.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Source")
                        .font(.headline)

                    TextEditor(text: sourceBinding)
                        .frame(minHeight: 180)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))

                    HStack {
                        Button("Parse") {
                            parseSource()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Run") {
                            runSelectedMethod()
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        TextField("Type name", text: $selectedTypeName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Method", text: $methodName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Arguments (comma-separated)", text: $argumentText)
                            .textFieldStyle(.roundedBorder)
                    }

                    if let error = workspace.lastError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Object Bench")
                        .font(.headline)

                    Text("Result: \(valueDisplay(workspace.lastResult))")
                        .font(.subheadline)

                    List(workspace.lastProperties.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        Text("\(key): \(valueDisplay(value))")
                    }
                    .frame(minWidth: 220, minHeight: 180)
                }
                .frame(width: 280)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Class Diagram")
                    .font(.headline)
                ClassDiagramView(definitions: workspace.definitions)
                    .frame(minHeight: 240)
            }
        }
        .padding(16)
        .onAppear {
            parseSource()
        }
    }

    private var sourceBinding: Binding<String> {
        Binding(
            get: { workspace.source },
            set: { workspace.setSource($0) }
        )
    }

    private func parseSource() {
        workspace.parseSource()
        if selectedTypeName.isEmpty {
            selectedTypeName = workspace.definitions.first?.name ?? ""
        }
        if methodName.isEmpty, let firstMethod = workspace.definitions.first?.methods.keys.sorted().first {
            methodName = firstMethod
        }
    }

    private func runSelectedMethod() {
        _ = workspace.run(classNamed: selectedTypeName, methodNamed: methodName, argumentText: argumentText)
    }

    private func valueDisplay(_ value: Value) -> String {
        switch value {
        case let .int(number):
            return String(number)
        case let .string(text):
            return text
        case let .bool(flag):
            return String(flag)
        case .void:
            return "void"
        }
    }

    private static let defaultSource = """
    class Counter {
        var count: Int = 0

        func increment() -> Int {
            count += 1
            return count
        }
    }
    """
}

#if DEBUG
#Preview {
    BlueSwiftWorkspaceView()
}
#endif

#else
public struct BlueSwiftWorkspaceView {
    public init(initialSource: String = "") {}
}
#endif
