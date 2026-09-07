import BlueSwiftCore

#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

private struct DiagramType: Identifiable, Hashable {
    let definition: ClassDefinition
    var id: String { definition.name }
}

private struct BoxCenterKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public struct ClassDiagramView: View {
    private let types: [DiagramType]
    private let columns: [GridItem]

    public init(definitions: [ClassDefinition]) {
        self.types = definitions.map(DiagramType.init(definition:)).sorted { $0.definition.name < $1.definition.name }
        self.columns = Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: max(1, min(3, (definitions.count + 1) / 2)))
    }

    public var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(types) { type in
                        ClassBoxView(definition: type.definition)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BoxCenterKey.self,
                                    value: [type.definition.name: CGPoint(x: proxy.frame(in: .named("diagram")).midX, y: proxy.frame(in: .named("diagram")).midY)]
                                )
                            })
                    }
                }
                .padding(24)
            }
            .coordinateSpace(name: "diagram")
            .overlayPreferenceValue(BoxCenterKey.self) { centers in
                GeometryReader { _ in
                    Path { path in
                        for type in types {
                            guard let parent = type.definition.superclassName,
                                  let from = centers[type.definition.name],
                                  let to = centers[parent] else { continue }
                            path.move(to: from)
                            path.addLine(to: to)
                        }
                    }
                    .stroke(Color.primary.opacity(0.7), lineWidth: 2)
                }
            }
        }
    }
}

private struct ClassBoxView: View {
    let definition: ClassDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(6)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(definition.properties, id: \.name) { property in
                    Text("• \(propertyDisplay(property))").font(.subheadline)
                }
                if definition.properties.isEmpty {
                    Text("—").font(.subheadline).foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(methodDisplays, id: \.self) { method in
                    Text(method).font(.subheadline)
                }
                if methodDisplays.isEmpty {
                    Text("—").font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(boxBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .frame(minWidth: 180)
    }

    private var methodDisplays: [String] {
        let methods = definition.methods.values
            .sorted { $0.name < $1.name }
            .map { "\($0.name)(\($0.parameterNames.joined(separator: ", ")))" }
        let initializers = definition.initializers.map { "init(\($0.parameterNames.joined(separator: ", ")))" }
        return initializers + methods
    }

    private func propertyDisplay(_ property: ClassDefinition.PropertyDefinition) -> String {
        if let typeName = property.typeName {
            return "\(property.name): \(typeName)"
        }
        return property.name
    }
}

private var boxBackgroundColor: Color {
#if canImport(UIKit)
    return Color(UIColor.secondarySystemBackground)
#elseif canImport(AppKit)
    return Color(NSColor.windowBackgroundColor)
#else
    return Color.gray.opacity(0.1)
#endif
}

#if DEBUG
struct ClassDiagramView_Previews: PreviewProvider {
    static var previews: some View {
        let base = ClassDefinition(
            kind: .class,
            name: "BaseCounter",
            superclassName: nil,
            properties: [.init(name: "count", typeName: "Int", defaultExpression: "0")],
            methods: [:],
            initializers: []
        )

        let adder = ClassDefinition(
            kind: .class,
            name: "Adder",
            superclassName: "BaseCounter",
            properties: [.init(name: "total", typeName: "Int", defaultExpression: "0")],
            methods: [
                "add": .init(name: "add", parameterNames: ["value"], statements: [.returnValue("total")])
            ],
            initializers: [.init(name: "init", parameterNames: [], statements: [])]
        )

        ClassDiagramView(definitions: [base, adder])
            .previewDisplayName("Class Diagram")
    }
}
#endif

#else
public struct ClassDiagramView {
    public let definitions: [ClassDefinition]

    public init(definitions: [ClassDefinition]) {
        self.definitions = definitions
    }
}
#endif
