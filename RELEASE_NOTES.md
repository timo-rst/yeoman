# Yeoman 0.3.0

## Highlights

- **Terminal Saver Module & `YeomanTermSaver` Helper:** Adds an edge-aware, multicolor filigree ASCII screensaver across native macOS terminals and IDE integrated terminals (`zsh`, `bash`, `fish`, and `tmux` managed integration with zero background daemon polling when idle).
- **8 Procedural Scenes & Custom Media Library:** Includes **Bonfire**, **Bouncing DVD Logo**, **Starfield**, **Wind Meadow**, **Matrix**, **Game of Life**, **Pipes**, and **3D Donut** (with independent per-scene speed, color palette, and 3D Donut shading styles), alongside bounded local **GIF/APNG/WebP/PNG/JPG/HEIC/MP4/MOV** imports with optional on-device Vision foreground cutout and forward-and-reverse loops.
- **16:9 Live Preview & Unified Inspector:** Redesigned Terminal Saver settings with a flush 16:9 CoreText ASCII Live Preview, side-by-side source inspector, clip renaming and search, clear navigation shortcut recorders, and consistent controls.
- **ASCII-Interactive Start, End & Switch Animations + Random Mode:** Adds **Swarm**, **Decode**, **Morph**, **Shatter**, **ASCII Rain**, and **Shockwave** alongside **Glitch** and **Random** across Start, End, and Switch transitions, each with independent speed sliders.
- **Auto-Advance Cutoff Control:** Adds a **Finish Loop** vs. **Hard Cut** selector under Auto-Advance so you can choose whether animated media finishes its current loop or cuts immediately at the deadline.
- **Documentation & Visual Overhaul:** Rewrote `README.md` with rendered engine and module graphics across all seven modules.

## Quality & Security

- Added full security, rendering, input-parser, rotation-queue, transition, random-mode, and auto-advance cutoff regressions in `Tests/TerminalSaverTests.swift` (`152/152` tests passing in `swift run YeomanTests` and `swift run --sanitize thread YeomanTests` with zero ThreadSanitizer warnings).
- Enforced bounded decoding, descriptor-relative `0700`/`0600` storage, signal-safe TTY raw mode and alternate-screen restoration, and strict ad-hoc signature verification across `Yeoman.app`, `YeomanInstaller`, and `YeomanTermSaver`.

## System Requirements

- macOS 14.0 (Sonoma) or newer
- Pre-built release targets Apple Silicon (`arm64`)

## SHA-256

- `Yeoman.zip`: `57810a6b754e7535c955abd071f5011d503cea3f0f1ab3b7d741a43e093f0957`
- `Yeoman.dmg`: `b1c14da977b65060a8075d956d909633fe62d9a8514b225c92d9c16e625c7408`
