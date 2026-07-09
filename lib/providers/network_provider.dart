import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/network_snapshot_repository.dart';

final networkSnapshotRepositoryProvider =
    Provider<NetworkSnapshotRepository>((ref) => NetworkSnapshotRepository());

final latestNetworkSnapshotProvider = FutureProvider.autoDispose<NetworkSnapshot?>((ref) async {
  final repo = ref.read(networkSnapshotRepositoryProvider);
  return repo.getLatest();
});

final networkHistoryProvider = FutureProvider.autoDispose<List<NetworkSnapshot>>((ref) async {
  final repo = ref.read(networkSnapshotRepositoryProvider);
  return repo.getLastHour();
});

enum DeliveryProbability { high, medium, low, veryLow }

extension DeliveryProbabilityX on DeliveryProbability {
  String get label {
    switch (this) {
      case DeliveryProbability.high:
        return 'HIGH';
      case DeliveryProbability.medium:
        return 'MEDIUM';
      case DeliveryProbability.low:
        return 'LOW';
      case DeliveryProbability.veryLow:
        return 'VERY LOW';
    }
  }
}

/// Maps the raw 0-100 network strength gauge to the four labeled bands
/// from the spec, and to a delivery-probability label for the Your Area
/// Network screen.
class NetworkStrengthBand {
  final String label;
  final int colorHex; // matches AppColors constants by value

  const NetworkStrengthBand(this.label, this.colorHex);

  static NetworkStrengthBand fromPercent(int pct) {
    if (pct >= 80) return const NetworkStrengthBand('Excellent', 0xFF25D366);
    if (pct >= 50) return const NetworkStrengthBand('Good', 0xFF25D366);
    if (pct >= 20) return const NetworkStrengthBand('Weak', 0xFFF0A500);
    return const NetworkStrengthBand('Very Weak', 0xFFDA3633);
  }

  static DeliveryProbability deliveryProbabilityFromPercent(int pct) {
    if (pct >= 80) return DeliveryProbability.high;
    if (pct >= 50) return DeliveryProbability.medium;
    if (pct >= 20) return DeliveryProbability.low;
    return DeliveryProbability.veryLow;
  }

  static String estimatedDeliveryTime(int pct) {
    if (pct >= 80) return 'Short (1-5 min)';
    if (pct >= 50) return 'Medium (5-30 min)';
    if (pct >= 20) return 'Long (30+ min)';
    return 'Very Long (hours)';
  }
}
