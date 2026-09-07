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
        guard let parent else {
            return false
        }
        return parent.set(name, value: value)
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

public struct ClassDefinition: Equatable {
    public enum Kind: Equatable {
        case `class`
        case `struct`
    }

    public struct PropertyDefinition: Equatable {
        public let name: String
        public let typeName: String?
        public let defaultExpression: String?

        public init(name: String, typeName: String?, defaultExpression: String?) {
            self.name = name
            self.typeName = typeName
            self.defaultExpression = defaultExpression
        }
    }

    public struct MethodDefinition: Equatable {
        public let name: String
        public let parameterNames: [String]
        /// Simplification: body is a compact statement model, not full Swift semantics.
        public let statements: [Statement]

        public init(name: String, parameterNames: [String], statements: [Statement]) {
            self.name = name
            self.parameterNames = parameterNames
            self.statements = statements
        }
    }

    public indirect enum Statement: Equatable {
        case variableDeclaration(name: String, expression: String?)
        case assignment(target: String, expression: String)
        case plusEquals(target: String, expression: String)
        case returnValue(String)
        case ifStatement(condition: String, thenStatements: [Statement], elseStatements: [Statement])
        case whileStatement(condition: String, body: [Statement])
        case expression(String)
    }

    public let kind: Kind
    public let name: String
    public let superclassName: String?
    public let properties: [PropertyDefinition]
    public let methods: [String: MethodDefinition]
    public let initializers: [MethodDefinition]

    public init(
        kind: Kind,
        name: String,
        superclassName: String?,
        properties: [PropertyDefinition],
        methods: [String: MethodDefinition],
        initializers: [MethodDefinition]
    ) {
        self.kind = kind
        self.name = name
        self.superclassName = superclassName
        self.properties = properties
        self.methods = methods
        self.initializers = initializers
    }
}

/// Entry point for BlueSwift's on-device Swift interpreter.
///
/// Simplifications/limitations:
/// - supports a focused subset needed by current tests and UI wiring
/// - control flow is limited to `if`/`else` and `while` with expression conditions
/// - no generics/protocols/async/macros/function dispatch beyond direct method selection
public struct Interpreter {
    private final class Storage {
        var definitions: [String: ClassDefinition] = [:]
    }

    private let storage = Storage()

    public init() {}

    @discardableResult
    public func parse(_ source: String) -> SourceFileSyntax {
        let syntax = Parser.parse(source: source)
        storage.definitions = extractDefinitions(from: syntax)
        return syntax
    }

    public var parsedDefinitions: [ClassDefinition] {
        storage.definitions.values.sorted { $0.name < $1.name }
    }

    public func definition(named name: String) -> ClassDefinition? {
        storage.definitions[name]
    }

    public func evaluate(
        classNamed className: String,
        callingMethod methodName: String,
        with args: [Value] = []
    ) -> (Value, finalProperties: [String: Value]) {
        guard let classDef = storage.definitions[className] else {
            return (.void, [:])
        }

        var properties = instantiateProperties(for: classDef)

        if methodName != "init", let zeroArgInitializer = resolveInitializer(for: classDef, argumentCount: 0) {
            _ = execute(statements: zeroArgInitializer.statements, environment: Environment(), properties: &properties)
        }

        if methodName == "init", let initializer = resolveInitializer(for: classDef, argumentCount: args.count) {
            let initializerEnv = Environment()
            for (index, name) in initializer.parameterNames.enumerated() where index < args.count {
                initializerEnv.define(name, value: args[index])
            }
            let result = execute(statements: initializer.statements, environment: initializerEnv, properties: &properties)
            return (result ?? .void, properties)
        }

        guard let method = resolveMethod(named: methodName, for: classDef) else {
            return (.void, properties)
        }

        let environment = Environment()
        for (index, name) in method.parameterNames.enumerated() where index < args.count {
            environment.define(name, value: args[index])
        }

        let result = execute(statements: method.statements, environment: environment, properties: &properties)
        return (result ?? .void, properties)
    }

    private func extractDefinitions(from syntax: SourceFileSyntax) -> [String: ClassDefinition] {
        var result: [String: ClassDefinition] = [:]

        for statement in syntax.statements {
            if let classDecl = statement.item.as(ClassDeclSyntax.self),
               let definition = extractDefinition(kind: .class, name: classDecl.name.text, inheritanceClause: classDecl.inheritanceClause, memberBlock: classDecl.memberBlock) {
                result[definition.name] = definition
            }

            if let structDecl = statement.item.as(StructDeclSyntax.self),
               let definition = extractDefinition(kind: .struct, name: structDecl.name.text, inheritanceClause: structDecl.inheritanceClause, memberBlock: structDecl.memberBlock) {
                result[definition.name] = definition
            }
        }

        return result
    }

    private func extractDefinition(
        kind: ClassDefinition.Kind,
        name: String,
        inheritanceClause: InheritanceClauseSyntax?,
        memberBlock: MemberBlockSyntax
    ) -> ClassDefinition? {
        let superclassName = inheritanceClause?.inheritedTypes.first?.type.trimmedDescription

        var properties: [ClassDefinition.PropertyDefinition] = []
        var methods: [String: ClassDefinition.MethodDefinition] = [:]
        var initializers: [ClassDefinition.MethodDefinition] = []

        for member in memberBlock.members {
            if let variableDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in variableDecl.bindings {
                    guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                    let typeName = binding.typeAnnotation?.type.trimmedDescription
                    let defaultExpression = binding.initializer?.value.trimmedDescription
                    properties.append(.init(name: identifierPattern.identifier.text, typeName: typeName, defaultExpression: defaultExpression))
                }
                continue
            }

            if let functionDecl = member.decl.as(FunctionDeclSyntax.self) {
                let method = ClassDefinition.MethodDefinition(
                    name: functionDecl.name.text,
                    parameterNames: parameterNames(from: functionDecl.signature.parameterClause.parameters),
                    statements: extractStatements(from: functionDecl.body?.statements ?? CodeBlockItemListSyntax([]))
                )
                methods[method.name] = method
                continue
            }

            if let initializerDecl = member.decl.as(InitializerDeclSyntax.self) {
                let initializer = ClassDefinition.MethodDefinition(
                    name: "init",
                    parameterNames: parameterNames(from: initializerDecl.signature.parameterClause.parameters),
                    statements: extractStatements(from: initializerDecl.body?.statements ?? CodeBlockItemListSyntax([]))
                )
                initializers.append(initializer)
            }
        }

        return .init(
            kind: kind,
            name: name,
            superclassName: superclassName,
            properties: properties,
            methods: methods,
            initializers: initializers
        )
    }

    private func parameterNames(from parameters: FunctionParameterListSyntax) -> [String] {
        parameters.compactMap { parameter in
            if let secondName = parameter.secondName, secondName.text != "_" {
                return secondName.text
            }
            return parameter.firstName.text == "_" ? nil : parameter.firstName.text
        }
    }

    private func extractStatements(from items: CodeBlockItemListSyntax) -> [ClassDefinition.Statement] {
        items.compactMap { extractStatement(from: $0) }
    }

    private func extractStatement(from item: CodeBlockItemSyntax) -> ClassDefinition.Statement? {
        let syntax = item.item

        if let decl = syntax.as(DeclSyntax.self), let variableDecl = decl.as(VariableDeclSyntax.self) {
            guard let binding = variableDecl.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                return nil
            }
            return .variableDeclaration(
                name: identifier.identifier.text,
                expression: binding.initializer?.value.trimmedDescription
            )
        }

        if let statement = syntax.as(StmtSyntax.self) {
            if let returnStmt = statement.as(ReturnStmtSyntax.self) {
                return .returnValue(returnStmt.expression?.trimmedDescription ?? "")
            }

            if let whileStmt = statement.as(WhileStmtSyntax.self) {
                return .whileStatement(
                    condition: whileStmt.conditions.trimmedDescription,
                    body: extractStatements(from: whileStmt.body.statements)
                )
            }

            if let expressionStmt = statement.as(ExpressionStmtSyntax.self) {
                return statementFromExpressionText(expressionStmt.expression.trimmedDescription)
            }
        }

        if let expression = syntax.as(ExprSyntax.self) {
            if let ifExpr = expression.as(IfExprSyntax.self) {
                return extractIfStatement(from: ifExpr)
            }
            return statementFromExpressionText(expression.trimmedDescription)
        }

        return nil
    }

    private func statementFromExpressionText(_ text: String) -> ClassDefinition.Statement {
        if let ifStatement = parseIfStatement(from: text) {
            return ifStatement
        }
        if let plusEqualsRange = text.range(of: "+=") {
            let target = String(text[..<plusEqualsRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let expression = String(text[plusEqualsRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return .plusEquals(target: target, expression: expression)
        }
        if let equalsRange = text.firstIndex(of: "="), !text.contains("==") {
            let target = String(text[..<equalsRange]).trimmingCharacters(in: .whitespaces)
            let expression = String(text[text.index(after: equalsRange)...]).trimmingCharacters(in: .whitespaces)
            return .assignment(target: target, expression: expression)
        }
        return .expression(text)
    }

    private func parseIfStatement(from text: String) -> ClassDefinition.Statement? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("if ") else { return nil }

        guard let openBraceIndex = trimmed.firstIndex(of: "{") else { return nil }
        let condition = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 3)..<openBraceIndex]).trimmingCharacters(in: .whitespaces)

        guard let thenCloseBrace = matchingBraceIndex(in: trimmed, forOpenBraceAt: openBraceIndex) else { return nil }
        let thenBody = String(trimmed[trimmed.index(after: openBraceIndex)..<thenCloseBrace])
        let thenStatements = parseInlineStatements(thenBody)

        let trailing = String(trimmed[trimmed.index(after: thenCloseBrace)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var elseStatements: [ClassDefinition.Statement] = []
        if trailing.hasPrefix("else") {
            let elsePart = String(trailing.dropFirst("else".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let elseOpen = elsePart.firstIndex(of: "{"),
               let elseClose = matchingBraceIndex(in: elsePart, forOpenBraceAt: elseOpen) {
                let elseBody = String(elsePart[elsePart.index(after: elseOpen)..<elseClose])
                elseStatements = parseInlineStatements(elseBody)
            }
        }

        return .ifStatement(condition: condition, thenStatements: thenStatements, elseStatements: elseStatements)
    }

    private func parseInlineStatements(_ body: String) -> [ClassDefinition.Statement] {
        body.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "{" && $0 != "}" }
            .map { statementFromExpressionText($0) }
    }

    private func matchingBraceIndex(in text: String, forOpenBraceAt start: String.Index) -> String.Index? {
        var depth = 0
        var current = start
        while current < text.endIndex {
            if text[current] == "{" { depth += 1 }
            if text[current] == "}" {
                depth -= 1
                if depth == 0 { return current }
            }
            current = text.index(after: current)
        }
        return nil
    }

    private func extractIfStatement(from ifExpr: IfExprSyntax) -> ClassDefinition.Statement {
        let thenStatements = extractStatements(from: ifExpr.body.statements)

        let elseStatements: [ClassDefinition.Statement]
        if let elseBody = ifExpr.elseBody {
            if let codeBlock = elseBody.as(CodeBlockSyntax.self) {
                elseStatements = extractStatements(from: codeBlock.statements)
            } else if let nestedIf = elseBody.as(IfExprSyntax.self) {
                elseStatements = [extractIfStatement(from: nestedIf)]
            } else {
                elseStatements = []
            }
        } else {
            elseStatements = []
        }

        return .ifStatement(
            condition: ifExpr.conditions.trimmedDescription,
            thenStatements: thenStatements,
            elseStatements: elseStatements
        )
    }

    private func instantiateProperties(for classDef: ClassDefinition) -> [String: Value] {
        var properties: [String: Value] = [:]

        for definition in inheritanceChain(for: classDef) {
            let environment = Environment()
            for (name, value) in properties {
                environment.define(name, value: value)
            }

            for property in definition.properties {
                if properties[property.name] != nil { continue }
                let value = property.defaultExpression.map { evaluateExpression($0, environment: environment, properties: properties) } ?? .void
                properties[property.name] = value
                environment.define(property.name, value: value)
            }
        }

        return properties
    }

    private func inheritanceChain(for classDef: ClassDefinition) -> [ClassDefinition] {
        guard let superclassName = classDef.superclassName,
              let superclass = storage.definitions[superclassName] else {
            return [classDef]
        }
        return inheritanceChain(for: superclass) + [classDef]
    }

    private func resolveInitializer(for classDef: ClassDefinition, argumentCount: Int) -> ClassDefinition.MethodDefinition? {
        if let own = classDef.initializers.first(where: { $0.parameterNames.count == argumentCount }) {
            return own
        }
        guard let superclassName = classDef.superclassName,
              let superclass = storage.definitions[superclassName] else {
            return nil
        }
        return resolveInitializer(for: superclass, argumentCount: argumentCount)
    }

    private func resolveMethod(named methodName: String, for classDef: ClassDefinition) -> ClassDefinition.MethodDefinition? {
        if let method = classDef.methods[methodName] {
            return method
        }
        guard let superclassName = classDef.superclassName,
              let superclass = storage.definitions[superclassName] else {
            return nil
        }
        return resolveMethod(named: methodName, for: superclass)
    }

    private func execute(
        statements: [ClassDefinition.Statement],
        environment: Environment,
        properties: inout [String: Value]
    ) -> Value? {
        for statement in statements {
            switch statement {
            case let .variableDeclaration(name, expression):
                let value = expression.map { evaluateExpression($0, environment: environment, properties: properties) } ?? .void
                environment.define(name, value: value)

            case let .assignment(target, expression):
                let value = evaluateExpression(expression, environment: environment, properties: properties)
                assignTarget(target, value: value, environment: environment, properties: &properties)

            case let .plusEquals(target, expression):
                let current = resolveTargetValue(target, environment: environment, properties: properties)
                let delta = evaluateExpression(expression, environment: environment, properties: properties)
                assignTarget(target, value: add(current, delta), environment: environment, properties: &properties)

            case let .returnValue(expression):
                return evaluateExpression(expression, environment: environment, properties: properties)

            case let .ifStatement(condition, thenStatements, elseStatements):
                if evaluateCondition(condition, environment: environment, properties: properties) {
                    let scoped = Environment(parent: environment)
                    if let value = execute(statements: thenStatements, environment: scoped, properties: &properties) {
                        return value
                    }
                } else {
                    let scoped = Environment(parent: environment)
                    if let value = execute(statements: elseStatements, environment: scoped, properties: &properties) {
                        return value
                    }
                }

            case let .whileStatement(condition, body):
                while evaluateCondition(condition, environment: environment, properties: properties) {
                    let scoped = Environment(parent: environment)
                    if let value = execute(statements: body, environment: scoped, properties: &properties) {
                        return value
                    }
                }

            case .expression:
                continue
            }
        }

        return nil
    }

    private func evaluateCondition(
        _ expression: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Bool {
        switch evaluateExpression(expression, environment: environment, properties: properties) {
        case let .bool(value):
            return value
        case let .int(value):
            return value != 0
        case .string, .void:
            return false
        }
    }

    private func evaluateExpression(
        _ expression: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .void }

        for comparator in ["<=", ">=", "==", "!=", "<", ">"] {
            if let parts = splitTopLevel(trimmed, by: comparator), parts.count == 2 {
                let lhs = evaluateExpression(parts[0], environment: environment, properties: properties)
                let rhs = evaluateExpression(parts[1], environment: environment, properties: properties)
                return .bool(compare(lhs, rhs, comparator: comparator))
            }
        }

        let terms = splitByTopLevelPlus(trimmed)
        guard let first = terms.first else { return .void }
        var result = evaluateTerm(first, environment: environment, properties: properties)
        for term in terms.dropFirst() {
            result = add(result, evaluateTerm(term, environment: environment, properties: properties))
        }
        return result
    }

    private func splitByTopLevelPlus(_ expression: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var inString = false
        var parenDepth = 0

        for char in expression {
            if char == "\"" {
                inString.toggle()
                current.append(char)
                continue
            }
            if !inString {
                if char == "(" { parenDepth += 1 }
                if char == ")" { parenDepth = max(0, parenDepth - 1) }
                if char == "+", parenDepth == 0 {
                    terms.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                    continue
                }
            }
            current.append(char)
        }

        if !current.isEmpty {
            terms.append(current.trimmingCharacters(in: .whitespaces))
        }

        return terms
    }

    private func splitTopLevel(_ expression: String, by token: String) -> [String]? {
        var inString = false
        var parenDepth = 0
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            if character == "\"" {
                inString.toggle()
            } else if !inString {
                if character == "(" { parenDepth += 1 }
                if character == ")" { parenDepth = max(0, parenDepth - 1) }

                if parenDepth == 0, expression[index...].hasPrefix(token) {
                    let lhs = String(expression[..<index]).trimmingCharacters(in: .whitespaces)
                    let rhsStart = expression.index(index, offsetBy: token.count)
                    let rhs = String(expression[rhsStart...]).trimmingCharacters(in: .whitespaces)
                    return [lhs, rhs]
                }
            }
            index = expression.index(after: index)
        }

        return nil
    }

    private func evaluateTerm(
        _ rawTerm: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        var term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)

        if term.hasPrefix("("), term.hasSuffix(")"), term.count > 2 {
            term = String(term.dropFirst().dropLast())
            return evaluateExpression(term, environment: environment, properties: properties)
        }

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

    private func compare(_ lhs: Value, _ rhs: Value, comparator: String) -> Bool {
        switch (lhs, rhs, comparator) {
        case let (.int(a), .int(b), "<"):
            return a < b
        case let (.int(a), .int(b), "<="):
            return a <= b
        case let (.int(a), .int(b), ">"):
            return a > b
        case let (.int(a), .int(b), ">="):
            return a >= b
        case let (.int(a), .int(b), "=="):
            return a == b
        case let (.int(a), .int(b), "!="):
            return a != b
        case let (.string(a), .string(b), "=="):
            return a == b
        case let (.string(a), .string(b), "!="):
            return a != b
        case let (.bool(a), .bool(b), "=="):
            return a == b
        case let (.bool(a), .bool(b), "!="):
            return a != b
        default:
            return false
        }
    }

    private func resolveTargetValue(
        _ target: String,
        environment: Environment,
        properties: [String: Value]
    ) -> Value {
        if target.hasPrefix("self.") {
            return properties[String(target.dropFirst("self.".count))] ?? .void
        }
        return environment.get(target) ?? properties[target] ?? .void
    }

    private func assignTarget(
        _ target: String,
        value: Value,
        environment: Environment,
        properties: inout [String: Value]
    ) {
        if target.hasPrefix("self.") {
            properties[String(target.dropFirst("self.".count))] = value
            return
        }

        if properties[target] != nil {
            properties[target] = value
            return
        }

        if !environment.set(target, value: value) {
            environment.define(target, value: value)
        }
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
