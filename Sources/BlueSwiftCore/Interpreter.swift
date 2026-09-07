import Foundation
import SwiftSyntax
import SwiftParser

public enum Value: Equatable {
    case int(Int)
    case string(String)
    case bool(Bool)
    case void
}

public final class Environment {
    private var values: [String: Value] = [:]
    private let parent: Environment?

    public init(parent: Environment? = nil) {
        self.parent = parent
    }

    @discardableResult
    public func set(_ name: String, value: Value) -> Bool {
        if values[name] != nil {
            values[name] = value
            return true
        }
        if let parent {
            return parent.set(name, value: value)
        }
        values[name] = value
        return true
    }

    public func define(_ name: String, value: Value) {
        values[name] = value
    }

    public func get(_ name: String) -> Value? {
        if let value = values[name] {
            return value
        }
        return parent?.get(name)
    }
}

public struct ClassDefinition {
    public struct PropertyDefinition {
        public let name: String
        public let defaultExpression: String?
    }

    public struct MethodDefinition {
        public let name: String
        public let parameterNames: [String]
        /// Simplification: method body is stored as raw statement text lines.
        public let statements: [String]
    }

    public let name: String
    public let properties: [PropertyDefinition]
    public let methods: [String: MethodDefinition]
}

/// Entry point for BlueSwift's on-device Swift interpreter.
///
/// Simplification for milestone 1:
/// - supports class property defaults and a tiny subset of statements/expressions
/// - no control flow, function calls, or advanced type system features
public struct Interpreter {
    private final class Storage {
        var classDefinitions: [String: ClassDefinition] = [:]
    }

    private let storage = Storage()

    public init() {}

    /// Parses Swift source into a syntax tree and extracts minimal class definitions.
    @discardableResult
    public func parse(_ source: String) -> SourceFileSyntax {
        let syntax = Parser.parse(source: source)
        storage.classDefinitions = extractClassDefinitions(from: syntax)
        return syntax
    }

    public func evaluate(
        classNamed className: String,
        callingMethod methodName: String,
        with args: [Value] = []
    ) -> (Value, finalProperties: [String: Value]) {
        guard let classDef = storage.classDefinitions[className] else {
            return (.void, [:])
        }

        var properties: [String: Value] = [:]
        let propertyEnvironment = Environment()
        for property in classDef.properties {
            let value = property.defaultExpression.map { evaluateExpression($0, environment: propertyEnvironment, properties: properties) } ?? .void
            properties[property.name] = value
            propertyEnvironment.define(property.name, value: value)
        }

        guard let method = classDef.methods[methodName] else {
            return (.void, properties)
        }

        let environment = Environment(parent: propertyEnvironment)
        for (index, name) in method.parameterNames.enumerated() where index < args.count {
            environment.define(name, value: args[index])
        }

        let result = execute(statements: method.statements, environment: environment, properties: &properties)
        return (result ?? .void, properties)
    }

    private func extractClassDefinitions(from syntax: SourceFileSyntax) -> [String: ClassDefinition] {
        var classes: [String: ClassDefinition] = [:]

        for statement in syntax.statements {
            guard let classDecl = statement.item.as(ClassDeclSyntax.self) else { continue }
            let className = classDecl.name.text

            var properties: [ClassDefinition.PropertyDefinition] = []
            var methods: [String: ClassDefinition.MethodDefinition] = [:]

            for member in classDecl.memberBlock.members {
                if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                    for binding in variableDecl.bindings {
                        guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                        let defaultExpression = binding.initializer?.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
                        properties.append(.init(name: identifierPattern.identifier.text, defaultExpression: defaultExpression))
                    }
                } else if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                    let parameterNames = functionDecl.signature.parameterClause.parameters.compactMap {
                        if let secondName = $0.secondName, secondName.text != "_" {
                            return secondName.text
                        }
                        return $0.firstName.text == "_" ? nil : $0.firstName.text
                    }
                    let statements = functionDecl.body?.statements.map {
                        $0.item.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    } ?? []
                    methods[functionDecl.name.text] = .init(
                        name: functionDecl.name.text,
                        parameterNames: parameterNames,
                        statements: statements
                    )
                }
            }

            classes[className] = .init(name: className, properties: properties, methods: methods)
        }

        return classes
    }

    private func execute(
        statements: [String],
        environment: Environment,
        properties: inout [String: Value]
    ) -> Value? {
        for statement in statements {
            if statement.hasPrefix("return ") {
                let expression = String(statement.dropFirst("return ".count))
                return evaluateExpression(expression, environment: environment, properties: properties)
            }

            if let plusEqualsRange = statement.range(of: "+=") {
                let lhs = String(statement[..<plusEqualsRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rhs = String(statement[plusEqualsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                let current = resolveTargetValue(lhs, environment: environment, properties: properties)
                let addition = evaluateExpression(rhs, environment: environment, properties: properties)
                assignTarget(lhs, value: add(current, addition), environment: environment, properties: &properties)
                continue
            }

            if let equalsRange = statement.firstIndex(of: "="), !statement.contains("==") {
                let lhs = String(statement[..<equalsRange]).trimmingCharacters(in: .whitespaces)
                let rhs = String(statement[statement.index(after: equalsRange)...]).trimmingCharacters(in: .whitespaces)
                let value = evaluateExpression(rhs, environment: environment, properties: properties)
                assignTarget(lhs, value: value, environment: environment, properties: &properties)
            }
        }

        return nil
    }

    private func evaluateExpression(
        _ expression: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        let terms = splitByPlus(expression)
        guard let first = terms.first else { return .void }

        var result = evaluateTerm(first, environment: environment, properties: properties)
        for term in terms.dropFirst() {
            let next = evaluateTerm(term, environment: environment, properties: properties)
            result = add(result, next)
        }

        return result
    }

    private func splitByPlus(_ expression: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var inString = false

        for char in expression {
            if char == "\"" {
                inString.toggle()
                current.append(char)
                continue
            }

            if char == "+", !inString {
                terms.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }

            current.append(char)
        }

        if !current.isEmpty {
            terms.append(current.trimmingCharacters(in: .whitespaces))
        }

        return terms
    }

    private func evaluateTerm(
        _ rawTerm: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)

        if term.hasPrefix("\""), term.hasSuffix("\""), term.count >= 2 {
            return .string(String(term.dropFirst().dropLast()))
        }
        if let intValue = Int(term) {
            return .int(intValue)
        }
        if term == "true" { return .bool(true) }
        if term == "false" { return .bool(false) }

        if term.hasPrefix("self.") {
            let key = String(term.dropFirst("self.".count))
            return properties[key] ?? .void
        }

        if let value = environment.get(term) {
            return value
        }

        return properties[term] ?? .void
    }

    private func resolveTargetValue(
        _ target: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        let key = String(target)
        if key.hasPrefix("self.") {
            return properties[String(key.dropFirst("self.".count))] ?? .void
        }
        return environment.get(key) ?? properties[key] ?? .void
    }

    private func assignTarget(
        _ target: String,
        value: Value,
        environment: Environment,
        properties: inout [String: Value]
    ) {
        let key = String(target)
        if key.hasPrefix("self.") {
            properties[String(key.dropFirst("self.".count))] = value
            return
        }

        if properties[key] != nil {
            properties[key] = value
            return
        }

        _ = environment.set(key, value: value)
    }

    private func add(_ lhs: Value, _ rhs: Value) -> Value {
        switch (lhs, rhs) {
        case let (.int(a), .int(b)):
            return .int(a + b)
        case let (.string(a), .string(b)):
            return .string(a + b)
        case let (.string(a), .int(b)):
            return .string(a + String(b))
        case let (.int(a), .string(b)):
            return .string(String(a) + b)
        default:
            return .void
        }
    }
}
