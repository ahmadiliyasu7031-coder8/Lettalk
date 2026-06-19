import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../providers/uranium_status_provider.dart';

/// Thin status bar shown at the top of the Home screen tabs so the
/// user always knows whether Uranium is running. It never blocks
/// anything — it is purely informational.
class UraniumStatusBar extends ConsumerWidget {
  const UraniumStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(uraniumStatusProvider);

    Color color;
    switch (status) {
      case UraniumStatus.active:
        color = AppColors.statusGood;
        break;
      case UraniumStatus.starting:
        color = AppColors.statusWeak;
        break;
      case UraniumStatus.offline:
        color = AppColors.statusBad;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: AppColors.surface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '${status.emoji} ${status.label}',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
