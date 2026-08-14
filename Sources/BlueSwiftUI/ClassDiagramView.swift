import SwiftUI
import BlueSwiftCore

// Adapter/model used by the UI. Replace or adapt if BlueSwiftCore exposes a different type.
public struct ParsedClass: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let properties: [String]
    public let methods: [String]
    public let superclass: String? // name of superclass, if any

    public init(name: String, properties: [String] = [], methods: [String] = [], superclass: String? = nil) {
        self.id = name
        self.name = name
        self.properties = properties
        self.methods = methods
        self.superclass = superclass
    }
}

// PreferenceKey for collecting box centers keyed by class name
private struct BoxCenterKey: PreferenceKey {
    static var defaultValue: [String: CGPoint] = [:]
    static func reduce(value: inout [String: CGPoint], nextValue: () -> [String: CGPoint]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public struct ClassDiagramView: View {
    public let classes: [ParsedClass]
    private let columns: [GridItem]

    public init(classes: [ParsedClass]) {
        self.classes = classes
        // Simple grid: 2-3 columns depending on size
        self.columns = Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: max(1, min(3, (classes.count + 1) / 2)))
    }

    public var body: some View {
        ScrollView([.vertical, .horizontal]) {
            ZStack {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(classes) { cls in
                        ClassBoxView(parsed: cls)
                            .background(GeometryReader { proxy in
                                Color.clear.preference(
                                    key: BoxCenterKey.self,
                                    value: [cls.name: CGPoint(x: proxy.frame(in: .named("diagram")).midX, y: proxy.frame(in: .named("diagram")).midY)]
                                )
                            })
                    }
                }
                .padding(24)
            }
            .coordinateSpace(name: "diagram")
            // Read the collected centers and draw connections using an overlay
            .overlayPreferenceValue(BoxCenterKey.self) { centers in
                GeometryReader { _ in
                    Path { path in
                        for cls in classes {
                            if let parent = cls.superclass,
                               let from = centers[cls.name],
                               let to = centers[parent] {
                                path.move(to: from)
                                path.addLine(to: to)
                            }
                        }
                    }
                    .stroke(Color.primary.opacity(0.7), lineWidth: 2)
                }
            }
        }
    }
}

private struct ClassBoxView: View {
    let parsed: ParsedClass

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(parsed.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(6)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(parsed.properties, id: \.self) { p in
                    Text("• \(p)").font(.subheadline)
                }
                if parsed.properties.isEmpty {
                    Text("—").font(.subheadline).foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                ForEach(parsed.methods, id: \.self) { m in
                    Text(m).font(.subheadline)
                }
                if parsed.methods.isEmpty {
                    Text("—").font(.subheadline).foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(UIColor.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
        .frame(minWidth: 160)
    }
}

// MARK: - Preview with a small hardcoded set (counter / adder / subclass examples)
#if DEBUG
struct ClassDiagramView_Previews: PreviewProvider {
    static var previews: some View {
        let counter = ParsedClass(
            name: "Counter",
            properties: ["count: Int"],
            methods: ["increment()", "reset()"],
            superclass: nil
        )

        let adder = ParsedClass(
            name: "Adder",
            properties: ["total: Int"],
            methods: ["add(_:)"] ,
            superclass: nil
        )

        let specialAdder = ParsedClass(
            name: "SpecialAdder",
            properties: ["multiplier: Int"],
            methods: ["add(_:)"] ,
            superclass: "Adder"
        )

        ClassDiagramView(classes: [counter, adder, specialAdder])
            .previewDisplayName("Class Diagram")
    }
}
#endif
