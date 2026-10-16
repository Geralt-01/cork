# Cork

**Run Windows games and applications on macOS — a free, open-source compatibility layer.**

Cork wraps [Wine](https://www.winehq.org) in a clean, native experience with a managed
runtime, isolated *bottles*, and per-bottle graphics backends (DXMT / DXVK / WineD3D).
It is inspired by the excellent work of [CrossOver](https://www.codeweavers.com/crossover),
[Whisky](https://github.com/Whisky-App/Whisky), and the wider Wine community.

> Cork is early software. Expect rough edges, and please file issues.

## Features

- **Managed runtime** — one command downloads and verifies a pinned Wine build, with
  SHA-256 checks and safe archive extraction. No Homebrew, no manual setup.
- **Bottles** — each app or game gets its own isolated Windows prefix.
- **Graphics backends** — choose DXMT (Direct3D → Metal), DXVK (Direct3D → Vulkan → Metal),
  or Wine's built-in WineD3D.
- **Per-bottle settings** — Windows version, msync/esync, async shaders, HUDs, debug channels.
- **Honest by design** — clear errors, verifiable downloads, and no hidden telemetry.

## Requirements

- macOS 13 or later
- Apple Silicon or Intel
- Apple Silicon users need **Rosetta 2** for the current x86_64 Wine runtime:
  `softwareupdate --install-rosetta --agree-to-license`

## Install

Cork is distributed as source while in preview.

```sh
git clone https://github.com/<you>/cork.git
cd cork
swift build -c release
.build/release/cork --help
```

Put the binary on your `PATH` or use the full path.

## Quick start

```sh
# 1. Download and verify the runtime (Wine + graphics components)
cork runtime install

# 2. Create a bottle
cork bottle create my-game

# 3. Run a Windows program
cork run my-game "~/Downloads/SomeGame/game.exe"
```

Run a game detached so your terminal stays free:

```sh
cork run my-game "~/Games/game.exe" --detach
```

Change a bottle's graphics backend or reported Windows version:

```sh
cork bottle set my-game backend=dxvk windows=win10
```

Check your Mac is ready:

```sh
cork doctor
```

## Commands

| Command | Description |
| --- | --- |
| `cork runtime install [components…] [--force]` | Download and install runtime components |
| `cork runtime status` | Show installed components |
| `cork runtime verify [--strict]` | Check components against the pinned manifest |
| `cork runtime uninstall <components…> [--all] [--yes]` | Remove components |
| `cork runtime files` | Print the Cork home directory |
| `cork bottle create <name> [--backend <backend>] [--windows <ver>] [--force] [--yes]` | Create a bottle |
| `cork bottle list` | List bottles |
| `cork bottle info <name>` | Show a bottle's settings |
| `cork bottle set <name> key=value…` | Change settings |
| `cork bottle logs <name> [--path]` | Show (or print the path to) a bottle's latest log |
| `cork bottle kill <name>` | Stop all processes in a bottle |
| `cork bottle delete <name> [--yes]` | Delete a bottle |
| `cork run <bottle> <exe> [--detach] [-- args…]` | Run a Windows program |
| `cork exec <bottle> <command> [args…]` | Run a Wine built-in (cmd, winecfg, reg, …) |
| `cork doctor` | Check the environment |

## How it works

```
┌───────────────────────────────────────────────┐
│                    cork (CLI)                  │
├───────────────────────────────────────────────┤
│                     CorkKit                    │
│  Runtime · Bottles · Graphics · Wine process   │
├───────────────────────────────────────────────┤
│  Wine (LGPL)  +  DXMT / DXVK / MoltenVK        │
│  translating Windows + Direct3D to Metal       │
└───────────────────────────────────────────────┘
```

- The **runtime** is downloaded to `~/Library/Application Support/Cork/Runtimes`
  and pinned by SHA-256 in `RuntimeManifest.json`. Cork never redistributes Wine.
- A **bottle** is a Wine prefix with a small `cork/metadata.json` describing its settings.
- **Graphics** components are copied into each bottle (or referenced via `WINEDLLPATH`),
  so backends are per-bottle and reversible.

Set `CORK_HOME` to relocate everything (for example, to keep a self-contained
install on an external drive).

## Why some games don't run

Games with kernel-level anti-cheat (Easy Anti-Cheat, BattlEye, Vanguard) **cannot** run
under Wine on macOS. Driver-level translation can't satisfy them. Cork surfaces this
instead of pretending otherwise.

## Legal

Cork's own code is **MIT** (see `LICENSE`). It downloads and runs unmodified third-party
components which keep their own licenses:

- **Wine** — LGPL-2.1-or-later
- **DXMT** — MIT (v0.80)
- **DXVK-macOS** — Zlib
- **MoltenVK** — Apache-2.0 (via Wine's Vulkan support)

Because Cork downloads these components at runtime rather than bundling them, you always
get the corresponding sources from the projects linked in `RuntimeManifest.json`.

Cork does **not** include or redistribute Apple's Game Porting Toolkit / D3DMetal.

## Credits

Cork stands on the shoulders of the Wine project, CodeWeavers, the DXMT and DXVK authors,
and the Whisky/Mallow communities.
