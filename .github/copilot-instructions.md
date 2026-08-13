# Copilot instructions for BlueSwift

## What this project is

BlueSwift is an original, GPL-3.0 iOS/iPadOS app inspired by BlueJ (the
Java teaching IDE). It is **not** a port of BlueJ's source — it's an
independent implementation of the same idea: visualize a class structure
and let the user instantiate objects and call methods on them live,
without writing a `main()`.

Do not copy code from BlueJ or any other GPL/proprietary codebase.
Everything here is written from scratch for this project.

## Hard platform constraint — read this before suggesting architecture

This is an **iOS/iPadOS app**. The sandbox forbids:
- Shelling out to `swiftc`, `swift repl`, or any subprocess
- Dynamically loading externally-compiled code at runtime
- Any approach that assumes a Mac-style filesystem or process model

Because of this, BlueSwift does **not** compile or run real Swift via the
Swift compiler. Live execution is done by a **custom tree-walking
interpreter** that runs entirely on-device, over a deliberately limited
subset of Swift. If you (Copilot) are about to suggest `Process`,
`swift repl`, dynamic library loading, or anything that assumes a
compiler is available at runtime — stop, that won't work on iOS.

## Architecture

- **Parsing**: use Apple's `swift-syntax` package (SPM dependency) to
  parse source into an AST. Do not write a custom Swift parser/tokenizer.
- **Interpreter**: `Sources/BlueSwiftCore/Interpreter/` — walks the
  swift-syntax AST and evaluates it directly. This is original code
  specific to this project.
- **Supported subset (v1)**: classes, structs, properties, methods,
  initializers, single inheritance, `if`/`else`, `for`, `while`, `Int`,
  `Double`, `String`, `Bool`, `Array`, `Dictionary`, basic operators,
  string interpolation.
- **Explicitly out of scope for v1**: generics, protocols with
  associated types, `async`/`await`, property wrappers, macros. Do not
  add support for these unless asked — keep the interpreter's scope
  tight while it's being proven correct.
- **UI**: SwiftUI only. Class diagram via `Canvas`. Object bench as a
  SwiftUI view bound to interpreter runtime values.
- **No network dependency.** Everything must work offline. Do not
  introduce a backend/API call as a way to solve an execution problem —
  that was a deliberate design decision, not an oversight.

## Build order / current milestone

Work is being built in this order. Do not jump ahead to UI work until
the interpreter core (milestone 1) has passing tests.

1. **[current] Interpreter core**: parse and evaluate a single class with
   properties and one method. No UI. Covered by unit tests in
   `Tests/BlueSwiftCoreTests`.
2. Expand interpreter: control flow, more types, multiple classes,
   inheritance.
3. Class diagram SwiftUI view, driven by swift-syntax parsing.
4. Object bench UI wired to the interpreter (instantiate, call methods,
   inspect/display results).
5. Project save/load, iPad-specific layout, polish.

## Conventions

- Swift API Design Guidelines naming.
- Every interpreter feature ships with unit tests in the same PR/commit
  — this is a correctness-sensitive component, not a UI shell.
- Keep `BlueSwiftCore` a pure Swift package with no UIKit/SwiftUI
  imports, so the interpreter can be tested without simulator/device.
- When in doubt about scope, prefer doing less over guessing — flag it
  instead of silently expanding the supported Swift subset.
