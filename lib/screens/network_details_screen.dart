import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../providers/network_provider.dart';
import '../services/ble_peripheral_service.dart';

class NetworkDetailsScreen extends ConsumerWidget {
  const NetworkDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latestAsync = ref.watch(latestNetworkSnapshotProvider);
    final historyAsync = ref.watch(networkHistoryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Network Details')),
      body: latestAsync.when(
        data: (latest) {
          final pct = latest?.strengthPct ?? 0;
          final lastScanned = latest != null
              ? DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(latest.timestamp))
              : '—';

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _DetailRow(label: 'Nearby Devices', value: '${latest?.nearbyCount ?? 0}'),
              _DetailRow(label: 'Last Scanned', value: lastScanned),
              _DetailRow(
                label: 'Broadcasting (so others can find you)',
                value: BlePeripheralService.instance.isAdvertising ? 'Yes' : 'No',
                valueColor: BlePeripheralService.instance.isAdvertising
                    ? AppColors.statusGood
                    : AppColors.statusBad,
              ),
              if (!BlePeripheralService.instance.isAdvertising &&
                  BlePeripheralService.instance.lastError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    BlePeripheralService.instance.lastError!,
                    style: const TextStyle(color: AppColors.statusBad, fontSize: 11),
                  ),
                ),
              _DetailRow(
                label: 'Status',
                value: NetworkStrengthBand.fromPercent(pct).label,
                valueColor: Color(NetworkStrengthBand.fromPercent(pct).colorHex),
              ),
              _DetailRow(label: 'Average Signal', value: '${latest?.avgRssi ?? '—'} dBm'),
              _DetailRow(
                label: 'Estimated Delivery Time',
                value: NetworkStrengthBand.estimatedDeliveryTime(pct),
              ),
              const SizedBox(height: 28),
              const Text('Network Strength — Last Hour',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: historyAsync.when(
                  data: (history) {
                    if (history.length < 2) {
                      return const Center(
                        child: Text('Not enough data yet — check back after a few scan cycles.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      );
                    }
                    final spots = <FlSpot>[];
                    for (var i = 0; i < history.length; i++) {
                      spots.add(FlSpot(i.toDouble(), history[i].strengthPct.toDouble()));
                    }
                    return LineChart(
                      LineChartData(
                        minY: 0,
                        maxY: 100,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (value, meta) => Text(
                                '${value.toInt()}%',
                                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                              ),
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: AppColors.primaryGreen,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primaryGreen.withOpacity(0.15),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
                  error: (e, _) => const Center(
                    child: Text('Failed to load history', style: TextStyle(color: AppColors.statusBad)),
                  ),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen)),
        error: (e, _) => const Center(
          child: Text('Failed to load network details', style: TextStyle(color: AppColors.statusBad)),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
