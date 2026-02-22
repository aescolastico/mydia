// Cross-platform network info detection.
//
// Uses conditional imports to select the appropriate platform implementation:
// - Native (iOS/Android/desktop): connectivity_plus
// - Web: Network Information API (Chromium-only, falls back to unknown)
// - Stub: returns unknown
export 'network_info_service_stub.dart'
    if (dart.library.io) 'network_info_service_native.dart'
    if (dart.library.js_interop) 'network_info_service_web.dart';
