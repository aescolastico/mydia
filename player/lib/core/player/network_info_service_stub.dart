/// Stub implementation for platforms without specific network detection.
///
/// Returns unknown network type as a safe default.
library;

/// Network connectivity type.
enum NetworkType { wifi, cellular, ethernet, unknown }

/// Get the current network type.
Future<NetworkType> getNetworkType() async => NetworkType.unknown;
