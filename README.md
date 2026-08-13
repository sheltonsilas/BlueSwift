# BlueSwift

An open-source, from-scratch iOS/iPadOS IDE for exploring Swift through live
object interaction — inspired by [BlueJ](https://www.bluej.org/), the
Java teaching IDE from the University of Kent, but independently designed
and implemented for Swift.

BlueSwift is **not** a port of BlueJ's source code. It's an original
implementation of the same core idea: let someone write a class, then
instantiate it and call methods on the live object directly — no `main()`,
no boilerplate — while seeing the class structure as a visual diagram.

> Working title. Rename freely before you publish.

## Why this is different from BlueJ under the hood

BlueJ runs on the JVM, which lets it dynamically load and invoke compiled
class files at runtime. iOS/iPadOS sandboxing rules out that approach
entirely — no arbitrary process execution, no dynamic loading of
externally-compiled code. So BlueSwift takes a different path:

- **Parsing**: [swift-syntax](https://github.com/apple/swift-syntax)
  (Apple, MIT-licensed) parses source into an AST — both for the class
  diagram and for the interpreter below.
- **Execution**: a **tree-walking interpreter**, written from scratch for
  this project, evaluates a subset of Swift directly on-device. This is
  what powers the live "object bench" — no compiler, no server, works
  fully offline.
- **UI**: SwiftUI throughout, with a Canvas-based class diagram and an
  object bench view for live instances.

## Supported Swift subset (v1 target)

- Classes and structs: properties, methods, initializers, inheritance
- Control flow: `if`/`else`, `for`, `while`
- Core types: `Int`, `Double`, `String`, `Bool`, `Array`, `Dictionary`
- Basic operators, string interpolation

**Not supported yet** (deliberately out of scope for v1): generics,
protocols with associated types, concurrency (`async`/`await`), property
wrappers, macros.

## Project layout

```
BlueSwift/
├── Sources/
│   └── BlueSwiftCore/     # Parser integration + interpreter (pure Swift, testable)
├── Tests/
│   └── BlueSwiftCoreTests/
├── Package.swift
└── .github/
    └── copilot-instructions.md
```

The `BlueSwiftCore` package is being built first, as a standalone Swift
package with unit tests, before any SwiftUI app code exists on top of it.
The interpreter needs to be correct and tested in isolation — that's the
part everything else depends on.

## Status

🚧 Early scaffold. Interpreter core is milestone 1 — see
`.github/copilot-instructions.md` for the current build plan.

## License

GPL-3.0. See [LICENSE](LICENSE).

## Contributing

Not yet open for contributions — core interpreter needs to prove itself
first. Issues/discussion welcome once there's something to run.
