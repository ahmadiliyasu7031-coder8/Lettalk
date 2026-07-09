import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/network_provider.dart';
import '../widgets/network_gauge.dart';
import 'network_details_screen.dart';

class NetworkTab extends ConsumerWidget {
  const NetworkTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(latestNetworkSnapshotProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Your Area Network')),
      body: RefreshIndicator(
        color: AppColors.primaryGreen,
        onRefresh: () async => ref.invalidate(latestNetworkSnapshotProvider),
        child: snapshotAsync.when(
          data: (snapshot) {
            final pct = snapshot?.strengthPct ?? 0;
            final nearby = snapshot?.nearbyCount ?? 0;
            final probability = NetworkStrengthBand.deliveryProbabilityFromPercent(pct);

            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 12),
                Center(child: NetworkGauge(percent: pct)),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        label: 'Devices Nearby',
                        value: '$nearby',
                        icon: Icons.devices_other,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StatCard(
                        label: 'Delivery Probability',
                        value: probability.label,
                        icon: Icons.send_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _LegendRow(),
                const SizedBox(height: 24),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppColors.primaryGreen),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const NetworkDetailsScreen()),
                    );
                  },
                  child: const Text('View Network Details',
                      style: TextStyle(color: AppColors.primaryGreen)),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
          error: (e, _) => const Center(
            child: Text('Failed to load network status', style: TextStyle(color: AppColors.statusBad)),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryGreen, size: 20),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bands = [
      ('80-100%', 'Excellent', AppColors.statusGood),
      ('50-79%', 'Good', AppColors.statusGood),
      ('20-49%', 'Weak', AppColors.statusWeak),
      ('0-19%', 'Very Weak', AppColors.statusBad),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: bands
            .map((b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: b.$3, shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(b.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(b.$2, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
