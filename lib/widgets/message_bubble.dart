import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Generic bubble — takes plain display values rather than a model
/// directly, so it can render both real (encrypted) messages and
/// outbox (waiting) drafts identically from the caller's point of view.
class MessageBubble extends StatelessWidget {
  final bool isOutgoing;
  final String displayText;
  final int createdAt;
  final String statusLabel;
  final Color statusColor;

  const MessageBubble({
    super.key,
    required this.isOutgoing,
    required this.displayText,
    required this.createdAt,
    required this.statusLabel,
    this.statusColor = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final timeLabel = DateFormat.jm().format(time);

    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isOutgoing ? AppColors.sentBubble : AppColors.receivedBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isOutgoing ? 14 : 2),
            bottomRight: Radius.circular(isOutgoing ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(displayText, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(timeLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                if (isOutgoing && statusLabel.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
