# Cork

**Run Windows games and applications on macOS — a free, open-source compatibility layer.**

Cork wraps [Wine](https://www.winehq.org) in a clean, native experience with a managed
runtime, isolated *bottles*, and per-bottle graphics backends (DXMT / DXVK / WineD3D).
It is inspired by the excellent work of [CrossOver](https://www.codeweavers.com/crossover),
[Whisky](https://github.com/Whisky-App/Whisky), and the wider Wine community.

> Cork is early software. Expect rough edges, and please file issues.

## Why Cork is nice

- **Simple, honest CLI + native SwiftUI app** — install, run, bundle apps and games with clear commands and a clean GUI.
- **Managed runtime** — one command downloads and verifies a pinned Wine build, with SHA-256 checks and safe archive extraction. No Homebrew, no manual setup.
- **Bottles** — each app or game gets its own isolated Windows prefix. Clean, reversible, and easy to delete.
- **Graphics backends** — choose DXMT (Direct3D → Metal), DXVK (Direct3D → Vulkan → Metal), or Wine's built-in WineD3D, per bottle.
- **Per-bottle settings** — Windows version, msync/esync, async shaders, HUDs, debug channels.
- **CrossOver catalog support** — load your `crossover.tie` to search, inspect, and run install recipes. Cork never bundles CodeWeavers data.
- **Dependencies made easy** — install common components (`vcrun`, `d3dx9/11`, `msxml6`, fonts, etc.) into any bottle.
- **Bundle to a Mac .app** — turn a Windows `.exe` into a double-clickable `.app` you can launch from Launchpad or `~/Applications`.
- **Diagnostics & associations** — `cork doctor`, file associations, and a built-in file browser for each bottle.
- **Honest by design** — clear errors, verifiable downloads, no hidden telemetry. No anti-cheat false promises.

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

Put the binary on your `PATH` (or use the full path to `.build/release/cork`).
For example, if Homebrew's `bin` directory is on your `PATH`:

```sh
ln -sf "$PWD/.build/release/cork" /opt/homebrew/bin/cork
```

or add the build directory to your shell profile (`~/.zshrc`):

```sh
export PATH="$PWD/.build/release:$PATH"
```

## Quick start

> New here? See the full **[Getting Started guide](docs/GETTING-STARTED.md)**.

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
| `cork bottle logs <name> [--path-only]` | Show (or print the path to) a bottle's latest log |
| `cork bottle kill <name>` | Stop all processes in a bottle |
| `cork bottle delete <name> [--yes]` | Delete a bottle |
| `cork run <bottle> <exe> [--detach] [-- args…]` | Run a Windows program |
| `cork exec <bottle> <command> [args…]` | Run a Wine built-in (cmd, winecfg, reg, …) |
| `cork app search <query>` | Search the app catalog |
| `cork app show <appid>` | Show a catalog app |
| `cork app recipe <appid>` | Show an app's install recipe |
| `cork app rating <appid>` | Show an app's compatibility rating |
| `cork install <bottle> <appid> [--catalog <file>] [--yes]` | Install a catalog app into a bottle |
| `cork deps list [--category <c>]` | List dependency components |
| `cork deps install <bottle> <component>` | Install a dependency (vcrun, d3dx9, …) |
| `cork assoc list <bottle>` | List file associations |
| `cork assoc set <bottle> <ext> <exe> [--name <label>]` | Add a file association |
| `cork assoc remove <bottle> <ext>` | Remove a file association |
| `cork bundle <bottle> <exe> [--name <n>] [--to <dir>] [--icon <file>]` | Make a double-clickable `.app` |
| `cork runtime wine list` | List Wine versions and install state |
| `cork runtime wine install <version>` | Install a Wine version |
| `cork runtime wine select <version>` | Select the default Wine version |
| `cork doctor [--bottle <name>]` | Check the environment |

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

## Games that run well (examples)

Cork's performance depends on the game, your Mac (Apple Silicon), chosen backend (DXMT is often best for D3D11 titles), and Wine build. These are examples reported as playable on Apple Silicon with Whisky/CrossOver-style setups; your mileage may vary.

| Game | Genre | Typical FPS (M-series) | Notes |
|---|---|---|---|
| **Counter-Strike 2** | FPS | 60–100 | May need tuning; anti-cheat blocks in many builds — **do not** expect online multiplayer to work. |
| **League of Legends** | MOBA | 60–120 | Often runs well with DXMT/DXVK; anti-cheat can change over time. |
| **The Elder Scrolls V: Skyrim** (vanilla/LE) | RPG | 40–90 | Very stable, great for testing. |
| **Fallout: New Vegas** | RPG | 60–120 | Runs excellently via Wine. |
| **Hollow Knight** | Metroidvania | 60+ | Solid, near native feel. |
| **Stardew Valley** | Farming | 60+ | Runs flawlessly. |
| **Portal 2** | Puzzle | 60–120 | Great performance. |
| **Among Us** | Party | 60+ | Usually fine (no kernel anti-cheat). |
| **Terraria** | Sandbox | 60+ | Great. |
| **Borderlands 2** | FPS/RPG | 40–80 | Playable with DXMT on Apple Silicon. |

*Anti-cheat games (EAC/BattlEye/Vanguard) often refuse to launch online under Wine on macOS. Cork surfaces honest errors rather than faking it.*

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
