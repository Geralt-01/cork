# Contributing to Cork

Thanks for helping make Windows games playable on macOS! This project is early and
moving quickly — questions, bug reports, and pull requests are all welcome.

## Getting started

Cork is a Swift package. You need macOS 13+ and Xcode command line tools.

```sh
git clone https://github.com/<you>/cork.git
cd cork
swift build
swift run cork-tests
```

Run the CLI during development:

```sh
swift run cork --help
```

## Project layout

```
Sources/
  CorkKit/        Core engine (no CLI/UI dependencies)
    Runtime/      Manifest, download, integrity, safe archive extraction
    Wine/         Wine installation discovery, environment, process control
    Bottle/       Bottle model, settings, lifecycle
    Graphics/     Graphics backend installation
  cork/           Command line interface (swift-argument-parser)
Tests/
  CorkTests/       Test runner executable (swift run cork-tests)
```

Guidelines:

- **CorkKit stays UI-agnostic.** The CLI and the future SwiftUI app both depend on it.
- **Never execute unverified downloads.** Everything must be pinned by SHA-256 in
  `RuntimeManifest.json` and extracted with the safety checks in `Runtime/Archive.swift`.
- **Keep the runtime in one place.** Components live in
  `~/Library/Application Support/Cork/Runtimes/<id>/<version>`.

## Testing

Cork ships its own tiny runner (`cork-tests`) instead of XCTest or Swift Testing, so the
suite works on a bare macOS install with only the Command Line Tools. Tests import CorkKit
with `@testable`, which the compiler only allows in debug builds — always use the default:

```sh
swift run cork-tests
```

Tests are hermetic: they create their own temporary directories and never touch
`~/Library/Application Support/Cork`.

Integration checks that inspect a real installed runtime are opt-in:

```sh
CORK_INTEGRATION=1 swift run cork-tests
```

## Commit style

- Small, focused commits with a clear subject line in the imperative mood.
- Describe *why* in the body when the change is non-obvious.

## Reporting bugs

Please include:

- macOS version and architecture (`sw_vers`, `uname -m`)
- The output of `cork doctor`
- The exact command you ran and the full output
- The relevant log (`cork bottle logs <name>`, or the path printed by `cork bottle info`)

## Updating the runtime

Runtime versions are pinned in `Sources/CorkKit/Resources/RuntimeManifest.json`.
When bumping a component:

1. Download the new artifact and compute its SHA-256.
2. Update `version`, `url`, `sha256`, `size`, and (if it changed) `installRoot`.
3. Run `cork runtime install --force` and verify a bottle still launches.
