# Touch Navigation Bug Analysis

## Bug Description

On mobile (web-on-phone and native phone app), navigating between movies and TV shows feels stuck. Touch events are captured but the screen doesn't visually update. Opening the sidebar drawer causes all previously-touched navigation events to suddenly appear (e.g., a tapped movie's detail screen becomes visible). This does NOT happen on desktop or web on laptop.

## Symptom Summary

1. User taps a movie/show in a grid or content rail
2. Nothing visible happens - screen appears frozen
3. Opening the sidebar drawer causes the deferred screen(s) to appear
4. Touch events ARE being captured (navigation code runs), but the UI doesn't repaint

## Key Observation

**The navigation IS happening (routes change, state updates) but the screen does NOT repaint until something else (like opening the drawer) forces a rebuild/repaint cycle.**

This is a **rendering pipeline issue**, not an input/gesture issue. Failed hypotheses around gesture handling (BackdropFilter compositing, onTapDown/onTapUp/onTapCancel patterns) were wrong because the touches ARE registering - they just don't cause a visual update.

## Architecture Context

### Router Setup (`lib/core/router/app_router.dart`)
- GoRouter with two navigators: `_rootNavigatorKey` (root) and `_shellNavigatorKey` (shell)
- `ShellRoute` wraps main screens (home, movies, shows, favorites, etc.) with `AppShell`
- Detail routes (`/movie/:id`, `/show/:id`) use `parentNavigatorKey: _rootNavigatorKey` (pushed outside shell)
- Tab navigation within shell uses `context.go()`, detail navigation uses `context.push()`

### AppShell (`lib/presentation/widgets/app_shell.dart`)
- `ConsumerStatefulWidget` with `_AppShellState`
- **Desktop path**: `Scaffold` with `Row([_DesktopSidebar, Expanded(child)])` - no GlobalKey, no extendBody, no bottomNav
- **Mobile path**: `Scaffold` with `key: AppShell.scaffoldKey` (static GlobalKey), `extendBody: true`, `drawer`, `bottomNavigationBar`
- Navigation: `_navigateTo(route)` calls `context.go(route)` on the `_AppShellState` context
- `_isOfflineMode()` calls `ref.watch(authStateProvider)` in `build()`

### ShellRoute Builder
```dart
ShellRoute(
  navigatorKey: _shellNavigatorKey,
  builder: (context, state, child) => AppShell(
    location: state.matchedLocation,
    child: child,
  ),
  routes: [/* home, movies, shows, favorites, etc. */],
)
```

## What's Different Between Desktop (works) and Mobile (broken)

| Aspect | Desktop | Mobile |
|--------|---------|--------|
| Scaffold key | none | `static final GlobalKey<ScaffoldState>` |
| extendBody | false (default) | `true` |
| bottomNavigationBar | none (sidebar in body) | `_ModernBottomNav` |
| drawer | none | `_MobileDrawer` |
| Inner screen AppBar | hidden (0-height) | visible with menu button |
| Nested Scaffolds | outer only (inner hides appbar) | outer + inner (both active) |

## Investigation Leads (Untested)

### 1. Static GlobalKey on Mobile Scaffold (HIGH PRIORITY)
`AppShell.scaffoldKey` is a `static final GlobalKey<ScaffoldState>()` used on the mobile Scaffold. GlobalKeys have special Flutter framework semantics around element reuse. The drawer's `openDrawer()` triggers `setState` on this ScaffoldState which forces a full rebuild - this matches the symptom of the drawer "unsticking" the UI. Investigate whether this GlobalKey is interfering with the normal rebuild cycle when GoRouter updates the shell.

### 2. GoRouter ShellRoute Rebuild Behavior (HIGH PRIORITY)
When navigating within the shell (e.g., `/movies` -> `/shows` via `context.go`), GoRouter needs to:
1. Call `notifyListeners()` on the router
2. Rebuild the `Router` widget
3. Update the root Navigator's pages
4. Re-call the ShellRoute builder with new `state.matchedLocation` and `child`
5. Trigger `didUpdateWidget` + `build` on `_AppShellState`

**If step 4 is skipped** (GoRouter caches the shell widget or the root Navigator doesn't consider the shell page "changed"), the AppShell widget never gets the new location/child. The drawer's `setState` on ScaffoldState would then force a rebuild using whatever the current `widget.child` is.

To test: Add `debugPrint` in `_AppShellState.didUpdateWidget` and `build` to verify they're called on every navigation.

### 3. ConsumerStatefulWidget + GoRouter Interaction (MEDIUM)
`_AppShellState` extends `ConsumerState<AppShell>` and calls `ref.watch(authStateProvider)` in `build()`. Riverpod's `ConsumerStatefulElement` might have subtle interactions with Flutter's normal rebuild cycle triggered by `didUpdateWidget`. If Riverpod's element override defers or batches rebuilds, the GoRouter-triggered rebuild might be delayed.

### 4. `extendBody: true` Compositing (MEDIUM)
With `extendBody: true`, the Scaffold body extends behind the bottom navigation bar. This creates specific compositing layer arrangements. If the body's compositing layer isn't being marked as needing repaint when its content changes, the screen wouldn't update visually even though the widget tree is rebuilt.

### 5. Nested Scaffolds on Mobile (LOW-MEDIUM)
On mobile, there are nested Scaffolds:
- Outer: AppShell's Scaffold (with GlobalKey, extendBody, drawer, bottomNav)
- Inner: Screen's Scaffold (with extendBodyBehindAppBar, own AppBar)

Each Scaffold manages its own layout and compositing. The interaction between outer `extendBody: true` and inner `extendBodyBehindAppBar: true` might cause layout/compositing conflicts specific to mobile.

### 6. Shell Navigator Page Keys (LOW)
If GoRouter generates the same page key for different child routes within the shell, the shell Navigator might not transition between them. Check what keys GoRouter assigns to `/movies` vs `/shows` pages in the shell navigator.

## Recommended Debugging Approach

### Step 1: Instrument Rebuilds
Add prints to verify the widget tree is actually rebuilding:

```dart
// In _AppShellState
@override
void didUpdateWidget(covariant AppShell oldWidget) {
  super.didUpdateWidget(oldWidget);
  debugPrint('[AppShell] didUpdateWidget: ${oldWidget.location} -> ${widget.location}');
  if (oldWidget.location != widget.location) {
    _autoExpandForRoute(widget.location);
  }
}

@override
Widget build(BuildContext context) {
  debugPrint('[AppShell] build called, location=${widget.location}');
  // ... rest of build
}
```

### Step 2: Test Without Mobile-Specific Features
Try each independently to isolate the cause:
1. Remove `key: AppShell.scaffoldKey` (will break drawer opening from inner screens - temporary test only)
2. Remove `extendBody: true`
3. Remove `bottomNavigationBar` (use a simple placeholder)

### Step 3: Force Rebuild on Location Change
If Step 1 shows `didUpdateWidget` is NOT being called, the issue is in GoRouter/ShellRoute not propagating updates. Fix: add a `ValueKey(location)` to the child to force subtree recreation:
```dart
Expanded(child: KeyedSubtree(key: ValueKey(widget.location), child: widget.child))
```

If `didUpdateWidget` IS being called but `build` isn't painting, the issue is in the rendering pipeline (compositing/repaint boundaries).

## Files Involved

- `player/lib/presentation/widgets/app_shell.dart` - Main shell widget (AppShell, _ModernBottomNav, _NavItem, _MobileDrawer, _DesktopSidebar)
- `player/lib/core/router/app_router.dart` - GoRouter configuration with ShellRoute
- `player/lib/presentation/screens/library/library_screen.dart` - Movies/Shows grid screen
- `player/lib/presentation/widgets/media_poster.dart` - Poster widget in grid screens
- `player/lib/presentation/widgets/media_card.dart` - Card widget in content rails
- `player/lib/presentation/screens/home_screen.dart` - Home screen with content rails
- `player/lib/core/layout/breakpoints.dart` - Desktop/mobile detection (tablet = 900px)

## Failed Hypotheses

1. **BackdropFilter compositing** - Removed BackdropFilter from 6 files. No improvement. The blur compositing layers were not the cause.
2. **LayoutBuilder deferring builds** - Replaced LayoutBuilder with MediaQuery-based check. No improvement (user didn't test this in isolation, but the underlying theory was weak).
3. **_NavItem onTapDown/onTapUp gesture loss** - Simplified gesture handling. Wrong diagnosis - the issue is rendering, not input capture.
4. **MediaCard onTapDown/onTapUp gesture loss** - Same wrong diagnosis as above.

## GoRouter Version
- `go_router: 17.0.1` (from pubspec.lock)
