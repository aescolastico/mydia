---
title: "Introducing Mydia Player"
date: 2026-02-22
summary: "A cross-platform media player with P2P remote access, offline downloads, and native playback on Android, iOS, macOS, and more."
tags: ["release", "player"]
---

**TL;DR** -- Mydia now ships a cross-platform player built with Flutter and a shared Rust networking core. It supports native playback via mpv, P2P remote access via iroh (no port forwarding needed), and offline downloads. Available on Android (APK), iOS (TestFlight), macOS, and web. [Download the latest release](https://github.com/getmydia/mydia/releases/latest).

---

Mydia now includes a built-in player written in Flutter. The Flutter codebase compiles to native apps for mobile and desktop, while also shipping as a web player embedded in Mydia itself.

## Cross-platform support

The player uses mpv via a Flutter binding for hardware-accelerated playback across a wide range of codecs and container formats. The web build falls back to server-side transcoding via ffmpeg.

Primary development and testing targets are **Android**, **iOS**, and **macOS**. Windows and Linux builds compile but may require platform-specific adjustments.

- **Android** -- APK available in each [GitHub release](https://github.com/getmydia/mydia/releases/latest)
- **iOS** -- Available via TestFlight
- **Web** -- Built into Mydia, served at `/player`

## Remote Access

The player can connect to a Mydia instance directly via URL, or through **Remote Access** -- a decentralized connectivity layer built on [iroh](https://www.iroh.computer/). Remote Access establishes encrypted P2P connections without exposing the Mydia instance to the public internet. Discovery uses a claim code to locate the server node.

Remote Access is disabled by default and requires both an environment variable toggle and explicit opt-in through the settings UI.

For optimal connectivity, configuring `network_mode: host` in Docker increases the likelihood of establishing a direct peer connection. Relay-based connections are bandwidth-throttled by default. An experimental unthrottled relay is available but should not be relied upon for production use.

The entire stack is open source, including relay infrastructure. Self-hosting your own relay is fully supported.

### How we got here

Remote Access went through several iterations before landing on iroh. The first attempt was a custom protocol using the Noise framework for encryption. It worked well for direct connections, but maintaining backward compatibility across protocol changes was daunting, and establishing direct connections required manual configuration on both ends.

From there, WebRTC seemed like the obvious choice but turned out to be too limited for our use case. libp2p had the right abstractions but brought in far too much complexity. A standalone DHT approach was explored next, but discovery was painfully slow.

iroh turned out to be the right fit. It handles hole punching, relay fallback, and encrypted transport out of the box. It just works, and it works well.

### Architecture

The networking core is implemented as a shared Rust crate (`mydia_p2p_core`). This ensures protocol parity between the server and all client platforms. Each side wraps the core through its own FFI interface -- Rustler NIF on the Elixir/Phoenix side, `flutter_rust_bridge` on the Dart/Flutter side. This keeps the performance-critical networking logic in Rust while exposing a simple, idiomatic API to each host language.

## Offline Downloads

The player supports downloading media for offline playback. This integrates with Mydia's **Collections** feature, allowing a curated set of media to be synced across multiple devices automatically.

## Current status

This is still early. The player works well for the platforms, formats, and network conditions it has been tested against, but not every combination has been exercised. Expect bugs.

If you run into something, please [open a GitHub issue](https://github.com/getmydia/mydia/issues).

## Roadmap

The player is not intended to be a full-featured media center. The focus is on reliable playback, offline support, and seamless remote connectivity for self-hosted media libraries.
