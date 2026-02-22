/// Web implementation using the Network Information API for network detection.
///
/// The Network Information API is Chromium-only, so this gracefully falls
/// back to unknown on unsupported browsers.
library;

import 'dart:js_interop';

@JS('navigator.connection')
external JSObject? get _navigatorConnection;

/// Network connectivity type.
enum NetworkType { wifi, cellular, ethernet, unknown }

/// Get the current network type using the Web Network Information API.
Future<NetworkType> getNetworkType() async {
  try {
    final connection = _navigatorConnection;
    if (connection == null) return NetworkType.unknown;

    final type = (connection as dynamic).type as String?;
    if (type == null) return NetworkType.unknown;

    return switch (type) {
      'wifi' => NetworkType.wifi,
      'cellular' => NetworkType.cellular,
      'ethernet' => NetworkType.ethernet,
      _ => NetworkType.unknown,
    };
  } catch (_) {
    return NetworkType.unknown;
  }
}
