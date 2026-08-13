import SwiftSyntax
import SwiftParser

public enum Value: Equatable {
    case int(Int)
    case string(String)
    case bool(Bool)
    case array([Value])
    case classInstance(ClassInstance)
    case structInstance(StructInstance)
    case void
}

public struct StructInstance: Equatable {
    public let typeName: String
    public var properties: [String: Value]
}

public final class ClassInstance: Equatable {
    public let typeName: String
    public var properties: [String: Value]

    public init(typeName: String, properties: [String: Value]) {
        self.typeName = typeName
        self.properties = properties
    }

    public static func == (lhs: ClassInstance, rhs: ClassInstance) -> Bool {
        lhs === rhs || (lhs.typeName == rhs.typeName && lhs.properties == rhs.properties)
    }
}

public final class Environment {
    private var bindings: [String: Value]
    private let parent: Environment?

    public init(bindings: [String: Value] = [:], parent: Environment? = nil) {
        self.bindings = bindings
        self.parent = parent
    }

    public func define(_ name: String, value: Value) {
        bindings[name] = value
    }

    @discardableResult
    public func assign(_ name: String, value: Value) -> Bool {
        if bindings[name] != nil {
            bindings[name] = value
            return true
        }
        if let parent {
            return parent.assign(name, value: value)
        }
        return false
    }

    public func lookup(_ name: String) -> Value? {
        if let value = bindings[name] {
            return value
        }
        return parent?.lookup(name)
    }
}

public struct ClassDefinition {
    public enum Kind {
        case `class`
        case `struct`
    }

    public struct StoredProperty {
        public let name: String
        public let declaredType: String?
        public let defaultValue: ExprSyntax?
    }

    public struct Parameter {
        public let name: String
    }

    public struct Method {
        public let name: String
        public let parameters: [Parameter]
        public let body: [CodeBlockItemSyntax]
    }

    public let kind: Kind
    public let name: String
    public let supertypeName: String?
    public let properties: [StoredProperty]
    public let methods: [Method]
}

public struct EvaluationResult {
    public let value: Value
    public let properties: [String: Value]
}

public enum InterpreterError: Error, Equatable {
    case noParsedSource
    case classNotFound(String)
    case methodNotFound(String)
    case missingPropertyDefaultValue(String)
    case argumentCountMismatch(expected: Int, actual: Int)
    case unknownIdentifier(String)
    case invalidAssignmentTarget
    case unsupportedSyntax(String)
    case invalidCondition(Value)
}

public struct Interpreter {
    private struct UnresolvedClassDefinition {
        let kind: ClassDefinition.Kind
        let name: String
        let supertypeName: String?
        let properties: [ClassDefinition.StoredProperty]
        let methods: [ClassDefinition.Method]
    }

    private final class Storage {
        var sourceFile: SourceFileSyntax?
        var typeDefinitions: [String: UnresolvedClassDefinition] = [:]
    }

    private let storage = Storage()

    public init() {}

    /// Parses Swift source into a syntax tree.
    @discardableResult
    public func parse(_ source: String) -> SourceFileSyntax {
        let tree = Parser.parse(source: source)
        storage.sourceFile = tree
        storage.typeDefinitions = buildTypeDefinitions(from: tree)
        return tree
    }

    public func evaluate(
        classNamed className: String,
        callingMethod methodName: String,
        with arguments: [Value] = []
    ) throws -> EvaluationResult {
        guard storage.sourceFile != nil else {
            throw InterpreterError.noParsedSource
        }

        let classDefinition = try resolveClassDefinition(named: className)
        var objectProperties = try instantiateProperties(for: classDefinition)
        let propertyEnvironment = Environment(bindings: objectProperties)

        let methodsWithName = classDefinition.methods.filter { $0.name == methodName }
        guard let method = methodsWithName.first(where: { $0.parameters.count == arguments.count }) else {
            if let firstMethod = methodsWithName.first {
                throw InterpreterError.argumentCountMismatch(expected: firstMethod.parameters.count, actual: arguments.count)
            }
            throw InterpreterError.methodNotFound(methodName)
        }

        let methodEnvironment = Environment(parent: propertyEnvironment)
        let selfValue: Value = switch classDefinition.kind {
        case .class:
            .classInstance(ClassInstance(typeName: classDefinition.name, properties: objectProperties))
        case .struct:
            .structInstance(StructInstance(typeName: classDefinition.name, properties: objectProperties))
        }
        methodEnvironment.define("self", value: selfValue)
        for (parameter, argument) in zip(method.parameters, arguments) {
            methodEnvironment.define(parameter.name, value: argument)
        }

        let returnValue = try executeMethodBody(method.body, environment: methodEnvironment, objectProperties: &objectProperties)
        return EvaluationResult(value: returnValue, properties: objectProperties)
    }

    private func buildTypeDefinitions(from sourceFile: SourceFileSyntax) -> [String: UnresolvedClassDefinition] {
        var definitions: [String: UnresolvedClassDefinition] = [:]
        for statement in sourceFile.statements {
            if let classDeclaration = statement.item.as(ClassDeclSyntax.self) {
                definitions[classDeclaration.name.text] = buildUnresolvedDefinition(
                    kind: .class,
                    name: classDeclaration.name.text,
                    supertypeName: classDeclaration.inheritanceClause?.inheritedTypes.first?.type.trimmedDescription,
                    members: classDeclaration.memberBlock.members
                )
                continue
            }

            if let structDeclaration = statement.item.as(StructDeclSyntax.self) {
                definitions[structDeclaration.name.text] = buildUnresolvedDefinition(
                    kind: .struct,
                    name: structDeclaration.name.text,
                    supertypeName: nil,
                    members: structDeclaration.memberBlock.members
                )
            }
        }
        return definitions
    }

    private func buildUnresolvedDefinition(
        kind: ClassDefinition.Kind,
        name: String,
        supertypeName: String?,
        members: MemberBlockItemListSyntax
    ) -> UnresolvedClassDefinition {
        var storedProperties: [ClassDefinition.StoredProperty] = []
        var methods: [ClassDefinition.Method] = []

        for member in members {
            if let variableDeclaration = member.decl.as(VariableDeclSyntax.self) {
                for binding in variableDeclaration.bindings {
                    guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                        continue
                    }
                    let typeName = binding.typeAnnotation?.type.trimmedDescription
                    let defaultValue = binding.initializer?.value
                    storedProperties.append(
                        ClassDefinition.StoredProperty(
                            name: pattern.identifier.text,
                            declaredType: typeName,
                            defaultValue: defaultValue
                        )
                    )
                }
                continue
            }

            if let functionDeclaration = member.decl.as(FunctionDeclSyntax.self) {
                let parameters = functionDeclaration.signature.parameterClause.parameters.compactMap { parameter in
                    if let secondName = parameter.secondName {
                        return ClassDefinition.Parameter(name: secondName.text)
                    }
                    return ClassDefinition.Parameter(name: parameter.firstName.text)
                }

                methods.append(
                    ClassDefinition.Method(
                        name: functionDeclaration.name.text,
                        parameters: parameters,
                        body: Array(functionDeclaration.body?.statements ?? [])
                    )
                )
            }
        }

        return UnresolvedClassDefinition(
            kind: kind,
            name: name,
            supertypeName: supertypeName,
            properties: storedProperties,
            methods: methods
        )
    }

    private func resolveClassDefinition(named className: String) throws -> ClassDefinition {
        var stack: Set<String> = []
        return try resolveClassDefinition(named: className, stack: &stack)
    }

    private func resolveClassDefinition(named className: String, stack: inout Set<String>) throws -> ClassDefinition {
        guard let unresolved = storage.typeDefinitions[className] else {
            throw InterpreterError.classNotFound(className)
        }
        if stack.contains(className) {
            throw InterpreterError.unsupportedSyntax("Cyclic inheritance for \(className)")
        }
        stack.insert(className)
        defer { stack.remove(className) }

        var inheritedProperties: [ClassDefinition.StoredProperty] = []
        var inheritedMethods: [ClassDefinition.Method] = []
        if let supertypeName = unresolved.supertypeName {
            let resolvedSuper = try resolveClassDefinition(named: supertypeName, stack: &stack)
            guard resolvedSuper.kind == .class else {
                throw InterpreterError.unsupportedSyntax("Only classes can be inherited")
            }
            inheritedProperties = resolvedSuper.properties
            inheritedMethods = resolvedSuper.methods
        }

        var propertyByName: [String: ClassDefinition.StoredProperty] = [:]
        var orderedPropertyNames: [String] = []
        for property in inheritedProperties + unresolved.properties {
            if propertyByName[property.name] == nil {
                orderedPropertyNames.append(property.name)
            }
            propertyByName[property.name] = property
        }

        var methodBySignature: [String: ClassDefinition.Method] = [:]
        var orderedMethodSignatures: [String] = []
        for method in inheritedMethods + unresolved.methods {
            let signature = methodSignatureKey(for: method)
            if methodBySignature[signature] == nil {
                orderedMethodSignatures.append(signature)
            }
            methodBySignature[signature] = method
        }

        return ClassDefinition(
            kind: unresolved.kind,
            name: unresolved.name,
            supertypeName: unresolved.supertypeName,
            properties: orderedPropertyNames.compactMap { propertyByName[$0] },
            methods: orderedMethodSignatures.compactMap { methodBySignature[$0] }
        )
    }

    private func instantiateProperties(for definition: ClassDefinition) throws -> [String: Value] {
        var objectProperties: [String: Value] = [:]
        let propertyEnvironment = Environment()
        for property in definition.properties {
            guard let defaultValue = property.defaultValue else {
                throw InterpreterError.missingPropertyDefaultValue(property.name)
            }
            let value = try evaluateExpression(defaultValue, environment: propertyEnvironment, objectProperties: &objectProperties)
            objectProperties[property.name] = value
            propertyEnvironment.define(property.name, value: value)
        }
        return objectProperties
    }

    private func methodSignatureKey(for method: ClassDefinition.Method) -> String {
        let parameterNames = method.parameters.map(\.name).joined(separator: ",")
        return "\(method.name)(\(parameterNames))"
    }

    private func executeMethodBody(
        _ statements: [CodeBlockItemSyntax],
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> Value {
        let outcome = try executeStatements(statements, environment: environment, objectProperties: &objectProperties)
        if case let .returned(value) = outcome {
            return value
        }
        return .void
    }

    private enum ExecutionOutcome {
        case `continue`
        case returned(Value)
    }

    private func executeStatements(
        _ statements: [CodeBlockItemSyntax],
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> ExecutionOutcome {
        for statement in statements {
            if let returnStatement = statement.item.as(ReturnStmtSyntax.self) {
                guard let expression = returnStatement.expression else {
                    return .returned(.void)
                }
                let value = try evaluateExpression(expression, environment: environment, objectProperties: &objectProperties)
                return .returned(value)
            }

            if let variableDeclaration = statement.item.as(VariableDeclSyntax.self) {
                try executeVariableDeclaration(variableDeclaration, environment: environment, objectProperties: &objectProperties)
                continue
            }

            if let ifExpression = statement.item.as(IfExprSyntax.self) {
                let ifOutcome = try executeIfExpression(ifExpression, environment: environment, objectProperties: &objectProperties)
                if case .returned = ifOutcome {
                    return ifOutcome
                }
                continue
            }

            if let whileStatement = statement.item.as(WhileStmtSyntax.self) {
                let whileOutcome = try executeWhileStatement(whileStatement, environment: environment, objectProperties: &objectProperties)
                if case .returned = whileOutcome {
                    return whileOutcome
                }
                continue
            }

            if let forStatement = statement.item.as(ForStmtSyntax.self) {
                let forOutcome = try executeForStatement(forStatement, environment: environment, objectProperties: &objectProperties)
                if case .returned = forOutcome {
                    return forOutcome
                }
                continue
            }

            if let expressionStatement = statement.item.as(ExpressionStmtSyntax.self) {
                if let ifExpression = expressionStatement.expression.as(IfExprSyntax.self) {
                    let ifOutcome = try executeIfExpression(ifExpression, environment: environment, objectProperties: &objectProperties)
                    if case .returned = ifOutcome {
                        return ifOutcome
                    }
                } else {
                    _ = try evaluateExpression(expressionStatement.expression, environment: environment, objectProperties: &objectProperties)
                }
                continue
            }

            if let expression = statement.item.as(ExprSyntax.self) {
                _ = try evaluateExpression(expression, environment: environment, objectProperties: &objectProperties)
                continue
            }

            throw InterpreterError.unsupportedSyntax(statement.item.trimmedDescription)
        }

        return .continue
    }

    private func executeVariableDeclaration(
        _ variableDeclaration: VariableDeclSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws {
        for binding in variableDeclaration.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                throw InterpreterError.unsupportedSyntax(binding.pattern.trimmedDescription)
            }
            guard let initializer = binding.initializer else {
                throw InterpreterError.unsupportedSyntax(binding.trimmedDescription)
            }
            let value = try evaluateExpression(initializer.value, environment: environment, objectProperties: &objectProperties)
            environment.define(pattern.identifier.text, value: value)
        }
    }

    private func executeIfExpression(
        _ ifExpression: IfExprSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> ExecutionOutcome {
        if try evaluateConditionElements(ifExpression.conditions, environment: environment, objectProperties: &objectProperties) {
            let scope = Environment(parent: environment)
            return try executeStatements(Array(ifExpression.body.statements), environment: scope, objectProperties: &objectProperties)
        }

        guard let elseBody = ifExpression.elseBody else {
            return .continue
        }

        if let elseIfExpression = elseBody.as(IfExprSyntax.self) {
            return try executeIfExpression(elseIfExpression, environment: environment, objectProperties: &objectProperties)
        }

        if let elseBlock = elseBody.as(CodeBlockSyntax.self) {
            let scope = Environment(parent: environment)
            return try executeStatements(Array(elseBlock.statements), environment: scope, objectProperties: &objectProperties)
        }

        throw InterpreterError.unsupportedSyntax(elseBody.trimmedDescription)
    }

    private func executeWhileStatement(
        _ whileStatement: WhileStmtSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> ExecutionOutcome {
        while try evaluateConditionElements(whileStatement.conditions, environment: environment, objectProperties: &objectProperties) {
            let scope = Environment(parent: environment)
            let loopOutcome = try executeStatements(Array(whileStatement.body.statements), environment: scope, objectProperties: &objectProperties)
            if case .returned = loopOutcome {
                return loopOutcome
            }
        }

        return .continue
    }

    private func executeForStatement(
        _ forStatement: ForStmtSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> ExecutionOutcome {
        guard let identifierPattern = forStatement.pattern.as(IdentifierPatternSyntax.self) else {
            throw InterpreterError.unsupportedSyntax(forStatement.pattern.trimmedDescription)
        }
        let iteratorName = identifierPattern.identifier.text
        let iterableValue = try evaluateExpression(forStatement.sequence, environment: environment, objectProperties: &objectProperties)

        guard case let .array(items) = iterableValue else {
            throw InterpreterError.unsupportedSyntax(forStatement.sequence.trimmedDescription)
        }

        for item in items {
            let scope = Environment(parent: environment)
            scope.define(iteratorName, value: item)
            let loopOutcome = try executeStatements(Array(forStatement.body.statements), environment: scope, objectProperties: &objectProperties)
            if case .returned = loopOutcome {
                return loopOutcome
            }
        }

        return .continue
    }

    private func evaluateConditionElements(
        _ conditions: ConditionElementListSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> Bool {
        for conditionElement in conditions {
            switch conditionElement.condition {
            case let .expression(expression):
                let conditionValue = try evaluateExpression(expression, environment: environment, objectProperties: &objectProperties)
                guard case let .bool(condition) = conditionValue else {
                    throw InterpreterError.invalidCondition(conditionValue)
                }
                if !condition {
                    return false
                }
            default:
                throw InterpreterError.unsupportedSyntax(conditionElement.trimmedDescription)
            }
        }
        return true
    }

    private func evaluateExpression(
        _ expression: ExprSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> Value {
        if let integerLiteral = expression.as(IntegerLiteralExprSyntax.self),
           let value = Int(integerLiteral.literal.text) {
            return .int(value)
        }

        if let stringLiteral = expression.as(StringLiteralExprSyntax.self) {
            return .string(stringLiteral.segments.compactMap { segment -> String? in
                segment.as(StringSegmentSyntax.self)?.content.text
            }.joined())
        }

        if let booleanLiteral = expression.as(BooleanLiteralExprSyntax.self) {
            return .bool(booleanLiteral.literal.tokenKind == .keyword(.true))
        }

        if let arrayLiteral = expression.as(ArrayExprSyntax.self) {
            let elements = try arrayLiteral.elements.map { element in
                try evaluateExpression(element.expression, environment: environment, objectProperties: &objectProperties)
            }
            return .array(elements)
        }

        if let tupleExpression = expression.as(TupleExprSyntax.self),
           tupleExpression.elements.count == 1,
           let singleElement = tupleExpression.elements.first {
            return try evaluateExpression(singleElement.expression, environment: environment, objectProperties: &objectProperties)
        }

        if let reference = expression.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if let value = environment.lookup(name) {
                return value
            }
            if let value = objectProperties[name] {
                return value
            }
            throw InterpreterError.unknownIdentifier(name)
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "self" {
            let name = memberAccess.declName.baseName.text
            guard let value = objectProperties[name] else {
                throw InterpreterError.unknownIdentifier(name)
            }
            return value
        }

        if let memberAccess = expression.as(MemberAccessExprSyntax.self),
           let baseExpression = memberAccess.base {
            let baseValue = try evaluateExpression(baseExpression, environment: environment, objectProperties: &objectProperties)
            let name = memberAccess.declName.baseName.text
            switch baseValue {
            case let .classInstance(instance):
                guard let value = instance.properties[name] else {
                    throw InterpreterError.unknownIdentifier(name)
                }
                return value
            case let .structInstance(instance):
                guard let value = instance.properties[name] else {
                    throw InterpreterError.unknownIdentifier(name)
                }
                return value
            default:
                throw InterpreterError.unsupportedSyntax(memberAccess.trimmedDescription)
            }
        }

        if let functionCall = expression.as(FunctionCallExprSyntax.self),
           let callee = functionCall.calledExpression.as(DeclReferenceExprSyntax.self) {
            guard functionCall.arguments.isEmpty else {
                throw InterpreterError.unsupportedSyntax(functionCall.trimmedDescription)
            }
            return try instantiateType(named: callee.baseName.text)
        }

        if let sequence = expression.as(SequenceExprSyntax.self) {
            return try evaluateSequenceExpression(sequence, environment: environment, objectProperties: &objectProperties)
        }

        if let prefixOperator = expression.as(PrefixOperatorExprSyntax.self) {
            let operand = try evaluateExpression(prefixOperator.expression, environment: environment, objectProperties: &objectProperties)
            switch prefixOperator.operator.text {
            case "!":
                guard case let .bool(value) = operand else {
                    throw InterpreterError.unsupportedSyntax(prefixOperator.trimmedDescription)
                }
                return .bool(!value)
            case "-":
                guard case let .int(value) = operand else {
                    throw InterpreterError.unsupportedSyntax(prefixOperator.trimmedDescription)
                }
                return .int(-value)
            default:
                throw InterpreterError.unsupportedSyntax(prefixOperator.operator.text)
            }
        }

        throw InterpreterError.unsupportedSyntax(expression.trimmedDescription)
    }

    private func evaluateSequenceExpression(
        _ sequence: SequenceExprSyntax,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> Value {
        let elements = Array(sequence.elements)
        guard elements.count >= 3, elements.count % 2 == 1 else {
            throw InterpreterError.unsupportedSyntax(sequence.trimmedDescription)
        }
        let leftExpression = elements[0]
        let firstOperator = elements[1]
        if elements.count == 3, firstOperator.is(AssignmentExprSyntax.self) {
            let rightValue = try evaluateExpression(elements[2], environment: environment, objectProperties: &objectProperties)
            return try assignValue(
                rightValue,
                to: leftExpression,
                withPlusEquals: false,
                environment: environment,
                objectProperties: &objectProperties
            )
        }

        if elements.count == 3,
           let binaryOperator = firstOperator.as(BinaryOperatorExprSyntax.self),
           binaryOperator.operator.text == "+=" {
            let rightValue = try evaluateExpression(elements[2], environment: environment, objectProperties: &objectProperties)
            return try assignValue(
                rightValue,
                to: leftExpression,
                withPlusEquals: true,
                environment: environment,
                objectProperties: &objectProperties
            )
        }

        var currentValue = try evaluateExpression(leftExpression, environment: environment, objectProperties: &objectProperties)
        var index = 1
        while index < elements.count {
            guard let binaryOperator = elements[index].as(BinaryOperatorExprSyntax.self) else {
                throw InterpreterError.unsupportedSyntax(elements[index].trimmedDescription)
            }
            let rightValue = try evaluateExpression(elements[index + 1], environment: environment, objectProperties: &objectProperties)
            currentValue = try applyBinaryOperator(binaryOperator.operator.text, left: currentValue, right: rightValue)
            index += 2
        }

        return currentValue
    }

    private func assignValue(
        _ newValue: Value,
        to target: ExprSyntax,
        withPlusEquals: Bool,
        environment: Environment,
        objectProperties: inout [String: Value]
    ) throws -> Value {
        let assignedValue: Value
        if withPlusEquals {
            let currentValue = try evaluateExpression(target, environment: environment, objectProperties: &objectProperties)
            assignedValue = try addValues(currentValue, newValue)
        } else {
            assignedValue = newValue
        }

        if let reference = target.as(DeclReferenceExprSyntax.self) {
            let name = reference.baseName.text
            if objectProperties[name] != nil {
                objectProperties[name] = assignedValue
            }
            if environment.assign(name, value: assignedValue) || objectProperties[name] != nil {
                return assignedValue
            }

            environment.define(name, value: assignedValue)
            return assignedValue
        }

        if let memberAccess = target.as(MemberAccessExprSyntax.self),
           let base = memberAccess.base?.as(DeclReferenceExprSyntax.self),
           base.baseName.text == "self" {
            let name = memberAccess.declName.baseName.text
            objectProperties[name] = assignedValue
            if !environment.assign(name, value: assignedValue) {
                environment.define(name, value: assignedValue)
            }
            return assignedValue
        }

        if let memberAccess = target.as(MemberAccessExprSyntax.self),
           let baseExpression = memberAccess.base,
           let baseReference = baseExpression.as(DeclReferenceExprSyntax.self) {
            let baseName = baseReference.baseName.text
            guard let baseValue = environment.lookup(baseName) else {
                throw InterpreterError.unknownIdentifier(baseName)
            }
            let memberName = memberAccess.declName.baseName.text
            switch baseValue {
            case let .classInstance(instance):
                instance.properties[memberName] = assignedValue
                _ = environment.assign(baseName, value: .classInstance(instance))
                return assignedValue
            case var .structInstance(instance):
                instance.properties[memberName] = assignedValue
                _ = environment.assign(baseName, value: .structInstance(instance))
                return assignedValue
            default:
                throw InterpreterError.invalidAssignmentTarget
            }
        }

        throw InterpreterError.invalidAssignmentTarget
    }

    private func instantiateType(named typeName: String) throws -> Value {
        let definition = try resolveClassDefinition(named: typeName)
        let properties = try instantiateProperties(for: definition)
        switch definition.kind {
        case .class:
            return .classInstance(ClassInstance(typeName: definition.name, properties: properties))
        case .struct:
            return .structInstance(StructInstance(typeName: definition.name, properties: properties))
        }
    }

    private func addValues(_ lhs: Value, _ rhs: Value) throws -> Value {
        switch (lhs, rhs) {
        case let (.int(left), .int(right)):
            return .int(left + right)
        case let (.string(left), .string(right)):
            return .string(left + right)
        default:
            throw InterpreterError.unsupportedSyntax("Unsupported '+' operands")
        }
    }

    private func applyBinaryOperator(_ op: String, left: Value, right: Value) throws -> Value {
        switch op {
        case "+":
            return try addValues(left, right)
        case "==":
            return .bool(left == right)
        case "!=":
            return .bool(left != right)
        case "<":
            guard case let .int(lhs) = left, case let .int(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '<' operands")
            }
            return .bool(lhs < rhs)
        case ">":
            guard case let .int(lhs) = left, case let .int(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '>' operands")
            }
            return .bool(lhs > rhs)
        case "<=":
            guard case let .int(lhs) = left, case let .int(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '<=' operands")
            }
            return .bool(lhs <= rhs)
        case ">=":
            guard case let .int(lhs) = left, case let .int(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '>=' operands")
            }
            return .bool(lhs >= rhs)
        case "&&":
            guard case let .bool(lhs) = left, case let .bool(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '&&' operands")
            }
            return .bool(lhs && rhs)
        case "||":
            guard case let .bool(lhs) = left, case let .bool(rhs) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '||' operands")
            }
            return .bool(lhs || rhs)
        case "..<":
            guard case let .int(start) = left, case let .int(end) = right else {
                throw InterpreterError.unsupportedSyntax("Unsupported '..<' operands")
            }
            return .array((start..<end).map { .int($0) })
        default:
            throw InterpreterError.unsupportedSyntax(op)
        }
    }
}
