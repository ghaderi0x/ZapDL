import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectionKind { none, wifi, ethernet, mobile, other }

/// Whether transfers may run on the given connections.
///
/// Wi-Fi-only mode allows Wi-Fi and Ethernet and refuses mobile data. A VPN
/// ("other") on top of Wi-Fi is fine; "other" alone is treated as unmetered
/// only when Wi-Fi-only mode is off, because its real transport is unknown.
bool transfersAllowed(Set<ConnectionKind> kinds, {required bool wifiOnly}) {
  final real = kinds.where((k) => k != ConnectionKind.none).toSet();
  if (real.isEmpty) return false;
  if (!wifiOnly) return true;
  return real.contains(ConnectionKind.wifi) || real.contains(ConnectionKind.ethernet);
}

/// True when the device is online only through mobile data.
bool onMobileDataOnly(Set<ConnectionKind> kinds) {
  final real = kinds.where((k) => k != ConnectionKind.none).toSet();
  return real.contains(ConnectionKind.mobile) &&
      !real.contains(ConnectionKind.wifi) &&
      !real.contains(ConnectionKind.ethernet);
}

/// Source of connectivity information; replaced by a fake in tests.
abstract class NetworkSource {
  Future<Set<ConnectionKind>> current();
  Stream<Set<ConnectionKind>> get changes;
}

class ConnectivityNetworkSource implements NetworkSource {
  ConnectivityNetworkSource([Connectivity? c]) : _c = c ?? Connectivity();
  final Connectivity _c;

  static Set<ConnectionKind> _map(List<ConnectivityResult> r) => {
        for (final x in r)
          switch (x) {
            ConnectivityResult.wifi => ConnectionKind.wifi,
            ConnectivityResult.ethernet => ConnectionKind.ethernet,
            ConnectivityResult.mobile => ConnectionKind.mobile,
            ConnectivityResult.none => ConnectionKind.none,
            _ => ConnectionKind.other,
          },
      };

  @override
  Future<Set<ConnectionKind>> current() async {
    try {
      return _map(await _c.checkConnectivity());
    } catch (_) {
      // If connectivity cannot be read, do not block downloads.
      return {ConnectionKind.other};
    }
  }

  @override
  Stream<Set<ConnectionKind>> get changes =>
      _c.onConnectivityChanged.map(_map).handleError((Object _) {});
}
