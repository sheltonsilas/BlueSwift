import SwiftSyntax
import SwiftParser

public enum Value: Equatable {
    case int(Int)
    case string(String)
    case bool(Bool)
    case array([Value])
    case void
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

    public let name: String
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
    private final class Storage {
        var sourceFile: SourceFileSyntax?
    }

    private let storage = Storage()

    public init() {}

    /// Parses Swift source into a syntax tree.
    @discardableResult
    public func parse(_ source: String) -> SourceFileSyntax {
        let tree = Parser.parse(source: source)
        storage.sourceFile = tree
        return tree
    }

    public func evaluate(
        classNamed className: String,
        callingMethod methodName: String,
        with arguments: [Value] = []
    ) throws -> EvaluationResult {
        guard let sourceFile = storage.sourceFile else {
            throw InterpreterError.noParsedSource
        }

        let classDefinition = try buildClassDefinition(from: sourceFile, named: className)
        var objectProperties: [String: Value] = [:]
        let propertyEnvironment = Environment()

        for property in classDefinition.properties {
            guard let defaultValue = property.defaultValue else {
                throw InterpreterError.missingPropertyDefaultValue(property.name)
            }
            let value = try evaluateExpression(defaultValue, environment: propertyEnvironment, objectProperties: &objectProperties)
            objectProperties[property.name] = value
            propertyEnvironment.define(property.name, value: value)
        }

        guard let method = classDefinition.methods.first(where: { $0.name == methodName }) else {
            throw InterpreterError.methodNotFound(methodName)
        }
        guard method.parameters.count == arguments.count else {
            throw InterpreterError.argumentCountMismatch(expected: method.parameters.count, actual: arguments.count)
        }

        let methodEnvironment = Environment(parent: propertyEnvironment)
        for (parameter, argument) in zip(method.parameters, arguments) {
            methodEnvironment.define(parameter.name, value: argument)
        }

        let returnValue = try executeMethodBody(method.body, environment: methodEnvironment, objectProperties: &objectProperties)
        return EvaluationResult(value: returnValue, properties: objectProperties)
    }

    private func buildClassDefinition(from sourceFile: SourceFileSyntax, named className: String) throws -> ClassDefinition {
        guard let classDeclaration = sourceFile.statements
            .compactMap({ $0.item.as(ClassDeclSyntax.self) })
            .first(where: { $0.name.text == className }) else {
            throw InterpreterError.classNotFound(className)
        }

        var storedProperties: [ClassDefinition.StoredProperty] = []
        var methods: [ClassDefinition.Method] = []

        for member in classDeclaration.memberBlock.members {
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

        return ClassDefinition(name: className, properties: storedProperties, methods: methods)
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

        throw InterpreterError.invalidAssignmentTarget
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
