import SwiftSyntax
import SwiftParser

/// Entry point for BlueSwift's on-device Swift interpreter.
///
/// This is the first piece to build (see .github/copilot-instructions.md,
/// milestone 1): parse a single class with properties and one method,
/// evaluate it, and prove correctness with unit tests before any UI exists.
///
/// This file is intentionally a stub — the real interpreter logic
/// (environment/scope model, statement + expression evaluation) does not
/// exist yet. Nothing here should be treated as final API.
public struct Interpreter {
    public init() {}

    /// Parses Swift source into a syntax tree.
    /// Evaluation on top of this tree is not implemented yet.
    public func parse(_ source: String) -> SourceFileSyntax {
        Parser.parse(source: source)
    }
}
