import Foundation
import BlueSwiftCore

public struct BlueSwiftWorkspace {
    private struct PersistedProject: Codable {
        let source: String
    }

    private var interpreter = Interpreter()

    public private(set) var source: String
    public private(set) var definitions: [ClassDefinition]
    public private(set) var lastResult: Value
    public private(set) var lastProperties: [String: Value]
    public private(set) var lastError: String?

    public init(source: String = "") {
        self.source = source
        self.definitions = []
        self.lastResult = .void
        self.lastProperties = [:]
        self.lastError = nil
    }

    public mutating func setSource(_ source: String) {
        self.source = source
    }

    @discardableResult
    public mutating func parseSource() -> Bool {
        _ = interpreter.parse(source)
        definitions = interpreter.parsedDefinitions
        lastError = definitions.isEmpty ? "No classes or structs found in source." : nil
        return !definitions.isEmpty
    }

    @discardableResult
    public mutating func run(classNamed className: String, methodNamed methodName: String, argumentText: String = "") -> Bool {
        if definitions.isEmpty {
            _ = parseSource()
        }

        guard definitions.contains(where: { $0.name == className }) else {
            lastError = "Type '\(className)' was not found in parsed source."
            return false
        }

        let args = parseArguments(argumentText)
        let (result, properties) = interpreter.evaluate(classNamed: className, callingMethod: methodName, with: args)

        if result == .void, properties.isEmpty {
            lastError = "Method '\(methodName)' did not run. Verify the type and method names."
            return false
        }

        lastResult = result
        lastProperties = properties
        lastError = nil
        return true
    }

    public func save(to url: URL) throws {
        let persisted = PersistedProject(source: source)
        let data = try JSONEncoder().encode(persisted)
        try data.write(to: url, options: .atomic)
    }

    public mutating func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let persisted = try JSONDecoder().decode(PersistedProject.self, from: data)
        source = persisted.source
        _ = parseSource()
    }

    private func parseArguments(_ text: String) -> [Value] {
        let rawParts = text
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        return rawParts.map(parseValue)
    }

    private func parseValue(_ text: String) -> Value {
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            return .string(String(text.dropFirst().dropLast()))
        }
        if let intValue = Int(text) {
            return .int(intValue)
        }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        return .string(text)
    }
}
