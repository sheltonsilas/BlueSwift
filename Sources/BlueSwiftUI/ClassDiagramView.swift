#if canImport(SwiftUI)
import BlueSwiftCore
import SwiftUI

public struct ClassDiagramView: View {
    private struct DiagramNode: Identifiable {
        let definition: ClassDefinition
        let origin: CGPoint
        let size: CGSize

        var id: String { definition.name }

        var frame: CGRect {
            CGRect(origin: origin, size: size)
        }

        var topCenter: CGPoint {
            CGPoint(x: frame.midX, y: frame.minY)
        }

        var bottomCenter: CGPoint {
            CGPoint(x: frame.midX, y: frame.maxY)
        }
    }

    private let definitions: [ClassDefinition]
    private let boxSize = CGSize(width: 240, height: 180)
    private let spacing = CGSize(width: 36, height: 36)

    public init(definitions: [ClassDefinition]) {
        self.definitions = definitions
    }

    public var body: some View {
        let nodes = layoutNodes()

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    drawInheritanceLines(in: &context, nodes: nodes)
                }
                .frame(width: contentSize(for: nodes).width, height: contentSize(for: nodes).height)

                ForEach(nodes) { node in
                    classBox(for: node.definition)
                        .frame(width: node.size.width, height: node.size.height)
                        .position(x: node.frame.midX, y: node.frame.midY)
                }
            }
            .frame(width: contentSize(for: nodes).width, height: contentSize(for: nodes).height)
            .padding()
        }
    }

    @ViewBuilder
    private func classBox(for definition: ClassDefinition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.kind == .class ? "class \(definition.name)" : "struct \(definition.name)")
                .font(.headline)
                .lineLimit(1)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if definition.properties.isEmpty {
                    Text("No properties")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(definition.properties, id: \.name) { property in
                        Text("• \(property.name)")
                            .lineLimit(1)
                    }
                }
            }
            .font(.subheadline)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if definition.methods.isEmpty {
                    Text("No methods")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(definition.methods, id: methodSignature) { method in
                        Text("• \(methodSignature(method))")
                            .lineLimit(1)
                    }
                }
            }
            .font(.subheadline)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.gray.opacity(0.5), lineWidth: 1)
        )
    }

    private func layoutNodes() -> [DiagramNode] {
        let sorted = definitions.sorted { $0.name < $1.name }
        guard !sorted.isEmpty else { return [] }

        let columns = max(1, Int(ceil(sqrt(Double(sorted.count)))))
        return sorted.enumerated().map { index, definition in
            let row = index / columns
            let column = index % columns
            let x = CGFloat(column) * (boxSize.width + spacing.width)
            let y = CGFloat(row) * (boxSize.height + spacing.height)
            return DiagramNode(definition: definition, origin: CGPoint(x: x, y: y), size: boxSize)
        }
    }

    private func contentSize(for nodes: [DiagramNode]) -> CGSize {
        guard let maxX = nodes.map(\.frame.maxX).max(),
              let maxY = nodes.map(\.frame.maxY).max() else {
            return CGSize(width: boxSize.width, height: boxSize.height)
        }
        return CGSize(width: maxX, height: maxY)
    }

    private func drawInheritanceLines(in context: inout GraphicsContext, nodes: [DiagramNode]) {
        let nodeByName = Dictionary(uniqueKeysWithValues: nodes.map { ($0.definition.name, $0) })
        let strokeStyle = StrokeStyle(lineWidth: 1.5, lineCap: .round)

        for node in nodes {
            guard let supertypeName = node.definition.supertypeName,
                  let superNode = nodeByName[supertypeName] else {
                continue
            }

            let start = node.topCenter
            let end = superNode.bottomCenter

            var path = Path()
            path.move(to: start)
            path.addLine(to: end)
            context.stroke(path, with: .color(.blue), style: strokeStyle)

            let arrowLength: CGFloat = 10
            let arrowWidth: CGFloat = 6
            let direction = CGVector(dx: start.x - end.x, dy: start.y - end.y)
            let magnitude = max(0.001, sqrt((direction.dx * direction.dx) + (direction.dy * direction.dy)))
            let unit = CGVector(dx: direction.dx / magnitude, dy: direction.dy / magnitude)
            let base = CGPoint(x: end.x + (unit.dx * arrowLength), y: end.y + (unit.dy * arrowLength))
            let perpendicular = CGVector(dx: -unit.dy, dy: unit.dx)
            let left = CGPoint(x: base.x + (perpendicular.dx * arrowWidth), y: base.y + (perpendicular.dy * arrowWidth))
            let right = CGPoint(x: base.x - (perpendicular.dx * arrowWidth), y: base.y - (perpendicular.dy * arrowWidth))

            var arrow = Path()
            arrow.move(to: end)
            arrow.addLine(to: left)
            arrow.addLine(to: right)
            arrow.closeSubpath()
            context.fill(arrow, with: .color(.blue))
        }
    }

    private func methodSignature(_ method: ClassDefinition.Method) -> String {
        let parameters = method.parameters.map(\.name).joined(separator: ", ")
        return "\(method.name)(\(parameters))"
    }
}

#Preview {
    ClassDiagramView(definitions: PreviewDefinitions.classDefinitions)
        .frame(minWidth: 750, minHeight: 520)
}

private enum PreviewDefinitions {
    static var classDefinitions: [ClassDefinition] {
        let source = """
        class Counter {
            var count: Int = 0

            func increment() {
                count += 1
            }
        }

        class Adder {
            var base: Int = 10

            func add(_ value: Int) -> Int {
                return base + value
            }
        }

        class SmartAdder: Adder {
            var multiplier: Int = 2

            func boosted(_ value: Int) -> Int {
                return add(value) * multiplier
            }
        }

        struct CounterSnapshot {
            var count: Int = 0
            func asText() -> String {
                return "\\(count)"
            }
        }
        """

        let interpreter = Interpreter()
        _ = interpreter.parse(source)
        return (try? interpreter.resolvedTypeDefinitions()) ?? []
    }
}
#endif
