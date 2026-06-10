---
title: "Plugins Are Coming to Mydia"
date: 2026-06-09
summary: "We're building a plugin platform so Mydia can do more without bloating the core. Sandboxed, you approve what each plugin can touch, and a webhook notifier is the first one. Here's the idea and how to get involved."
tags: ["development", "plugins"]
---

**TL;DR** -- Mydia is getting plugins. They run safely inside the app, you decide exactly what each one is allowed to do, and the first one is a notifier that pings Discord (or a webhook) when something is added to your library. This is an early version we want to learn from, an SDK to make writing plugins easy is on the way, and we'd love your help.

---

## Why plugins

Mydia already connects to a lot of things: indexers, metadata sources, download clients, media servers. Every one of those was added by changing Mydia itself. That works, but it means the core keeps growing, and the things _you_ might want it to talk to are limited to whatever we've had time to build in.

Plugins flip that around. Instead of waiting for us to add support for the one service you care about, a plugin can add it from the outside, without us touching the core and without you trusting a black box. The core stays lean, and Mydia can reach a lot further.

This has been on our minds from the start. There was even an early Lua proof-of-concept that never really went anywhere. This time we're taking cues from [Zed](https://zed.dev/), the Rust code editor, which runs its plugins as WebAssembly to keep them fast and safe. It's a model we think fits Mydia well, and it's where the platform is headed.

## Safe by default

The thing we cared about most is that installing a plugin should never feel like a leap of faith.

Every plugin runs in a sandbox. On its own it can't read your files, reach the network, or poke at your library. It can only do the specific things it asks for, and only after you say yes.

When you install one, Mydia shows you in plain language exactly what it wants. Something like:

- "React to: media added, download completed"
- "Make network requests to: `discord.com`"
- "Read your library data"

Nothing happens until you approve that list. If a plugin tries to do anything it didn't ask for, or anything you didn't grant, it's simply blocked. Change your mind later and revoke a permission, and it takes effect right away.

Network access gets extra care. If a plugin is allowed to talk to `discord.com`, that's _all_ it can reach. It can't be tricked into poking at your router, your other home-lab services, or anything else on your network. And you can always see where a plugin has actually been connecting.

If a plugin misbehaves, crashes, or gets stuck, it's contained. Mydia keeps running, and so does every other plugin.

## The first plugin: a notifier

To make sure the platform works in practice and not just on paper, we built the first plugin ourselves: a notifier. When something is added to your library or a download finishes, it sends a message to Discord or any webhook URL you point it at. If the destination is briefly down, it keeps retrying so you don't miss the notification.

It's small on purpose. The point was to prove the whole path end to end, and to be a working example for the plugins that come next.

## Knowing it's working

A plugin you can't observe is a plugin you can't trust, so each one has its own activity view in the admin UI. You can see when it ran, what it did, and whether it succeeded or failed, with the error right there if something went wrong. There's also a Test button that triggers a plugin on demand, so right after installing you can confirm it works without waiting for real activity.

## An SDK is coming

Right now, writing a plugin means working close to the metal. That's fine for us proving things out, but it's not the experience we want for anyone else.

So an SDK is on the way to make building a plugin straightforward: write your logic, build it, drop it into a running Mydia, and test it. To start it'll support **Rust**, and because plugins run on WebAssembly, support for other languages that compile to WebAssembly is planned after that. The aim is that adding a new integration to Mydia is something a motivated person can do in an afternoon.

Alongside that we're working toward a community catalog you can browse and install from directly inside Mydia, and more flexible setups like pointing the notifier at your own server (your own ntfy instance, for example).

## Help us shape it

This is an early version, scoped on purpose, and we fully expect it to change as we learn what people actually want to build.

So tell us. What do you wish Mydia could talk to? Where does the permission model feel too strict or not strict enough? If you're the kind of person who'd enjoy building a plugin or improving the core, even better. The whole project is open source.

Come build with us [on GitHub](https://github.com/getmydia/mydia).
