import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The three states the Uranium relay engine can be in at any point.
/// This is exposed to the UI so the user always knows what is happening
/// — the app NEVER blocks on any of these states.
enum UraniumStatus {
  starting,  // engine is bootstrapping in background
  active,    // BLE advertising + scanning cycle is running
  offline,   // no Bluetooth / permissions denied / engine stopped
}

extension UraniumStatusX on UraniumStatus {
  String get label {
    switch (this) {
      case UraniumStatus.starting:
        return 'Starting Uranium...';
      case UraniumStatus.active:
        return 'Uranium Active';
      case UraniumStatus.offline:
        return 'Uranium Offline';
    }
  }

  String get emoji {
    switch (this) {
      case UraniumStatus.starting:
        return '🟡';
      case UraniumStatus.active:
        return '🟢';
      case UraniumStatus.offline:
        return '🔴';
    }
  }
}

final uraniumStatusProvider =
    StateProvider<UraniumStatus>((ref) => UraniumStatus.starting);
