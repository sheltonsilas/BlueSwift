# First Copilot Agent mode prompt

Open this repo in VS Code, make sure `.github/copilot-instructions.md`
exists (it does), switch Copilot Chat to **Agent** mode, and paste this:

---

In BlueSwiftCore, implement basic evaluation on top of the existing
`Interpreter.parse` method. Scope for this task only:

1. A `Value` enum representing runtime values: `.int(Int)`, `.string(String)`,
   `.bool(Bool)`, `.void`.
2. An `Environment` class holding variable bindings (a dictionary of name
   to `Value`, with support for a parent environment for scoping).
3. A `ClassDefinition` type built by walking the parsed `SourceFileSyntax`
   for a single top-level `class` declaration: its stored properties
   (name, declared type, default value expression) and its methods
   (name, parameter list, body statements).
4. An `evaluate(classNamed:callingMethod:with:)` method on `Interpreter`
   that: instantiates the named class using property default values,
   calls the named method with the given arguments, executes the
   method body (support only simple statements for now: variable
   assignment, `+=`, integer/string literals, property access via
   `self`), and returns the resulting `Value` plus the object's
   final property state.

Do not implement control flow (if/for/while) yet — that's the next
milestone. Do not add support for structs, inheritance, or any type
beyond Int/String/Bool for this task.

Update `InterpreterTests.swift`: replace the TODO with a real test that
parses the `Counter` class, calls `increment()`, and asserts the
resulting `count` property equals `1`. Add one more test for a method
that takes a parameter and returns a value (e.g. a class with an `add(_:)`
method returning `Int`).

Run `swift test` and fix anything that fails before finishing.

---

## Why scoped this tightly

Agent mode does best on well-defined, testable tasks (per GitHub's own
2026 guidance). "Build the interpreter" is too broad — it'll wander.
"Build exactly this evaluation path, with these two tests as the
definition of done" gives it a clear stop condition.

Once this lands and `swift test` passes, the next prompt extends
evaluation to `if`/`else` and `for`/`while` — same pattern, same file,
new test cases.
