# Cork architecture

Cork runs Windows software on macOS via Wine. This document is the shared
contract for the "make Cork like CrossOver" effort.

## Targets (SwiftPM)

| Target | Kind | Role |
| --- | --- | --- |
| `CorkKit` | library | Runtime/bottle/prefix engine. Mature; treat as stable. |
| `CorkEngine` | library | Application layer: recipe catalogs, compatibility data, installers, app bundling, dependencies, associations. |
| `cork` | executable | CLI (swift-argument-parser). |
| `cork-app` | executable | macOS SwiftUI front-end. |
| `cork-tests` | executable | Custom test runner (`Tests/CorkTests/main.swift`). |

## Module map (`Sources/CorkEngine`)

```
RecipeApp.swift        Frozen model for a catalog entry.
AppCatalog.swift       Frozen AppCatalog protocol + CatalogQuery.
CrossTieCatalog.swift  CrossTie (`crossover.tie`) XML catalog (frozen API).
CrossTieParser.swift   Streaming c4p parser (owned by engine track).
CompatDatabase.swift   Compatibility DB reader (owned by engine track).
CrossOverData.swift    Discovers user-supplied CrossOver files.
```

Planned modules: `Installer/`, `Dependencies/`, `Bundle/`, `Associations/`,
`Diagnostics/`.

## Frozen API contract

These symbols are consumed by both the CLI and the GUI. **Do not rename or
remove**; only add (with defaults):

- `RecipeApp` — `id`, `name`, `localizedNames`, `summary`, `category`,
  `rating`, `medal`, `bottleTemplate`, `dependencies`, `hasInstaller`,
  `platforms`, `defaultAssociations`, …
- `CatalogQuery`, `AppCatalog` (`sourceDescription`, `appCount`, `categories()`,
  `search(_:)`, `app(id:)`).
- `CrossTieCatalog(fileURL:)`, `CrossTieParser.parse(fileURL:)`,
  `CrossTieIndex(apps:)`.
- `CompatDatabase(fileURL:)`, `CompatEntry`.
- `CrossOverData.defaultTieURL()` / `defaultCompatDatabaseURL()`.

## Data policy (important)

Cork **never bundles or redistributes CodeWeavers data**. `crossover.tie`,
`compatdb-*.dat`, and `cxfixes.xml` are read only when the *user* supplies them
(or they already exist on the user's machine). Any catalog Cork ships must be
Cork's own format/content.

Legal engine note: CodeWeavers' patched Wine is proprietary and is **not**
reconstructable. Cork uses Wine + DXMT/DXVK/MoltenVK.

## Parallel-work ownership rules

- **Only the integrator edits `Package.swift`.**
- Each workstream edits an exclusive set of files.
- Keep `CorkEngine` compiling at all times (additive changes only to frozen API).
- Build with an isolated scratch path: `swift build --scratch-path .build-<track>`.

## Verify

```sh
swift build
swift run cork app search word --catalog "<your crossover.tie>"
.build/debug/cork-tests
```
