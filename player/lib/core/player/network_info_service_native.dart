/// Native implementation using connectivity_plus for network detection.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network connectivity type.
enum NetworkType { wifi, cellular, ethernet, unknown }

/// Get the current network type using connectivity_plus.
Future<NetworkType> getNetworkType() async {
  try {
    final results = await Connectivity().checkConnectivity();
    if (results.isEmpty) return NetworkType.unknown;

    final result = results.first;
    return switch (result) {
      ConnectivityResult.wifi => NetworkType.wifi,
      ConnectivityResult.mobile => NetworkType.cellular,
      ConnectivityResult.ethernet => NetworkType.ethernet,
      _ => NetworkType.unknown,
    };
  } catch (_) {
    return NetworkType.unknown;
  }
}
