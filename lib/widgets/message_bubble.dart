import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  final LettalkMessage message;
  final bool isOutgoing;
  final String displayText;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isOutgoing,
    required this.displayText,
  });

  String get _statusLabel {
    switch (message.status) {
      case MessageStatus.sent:
        return '✓ Sent';
      case MessageStatus.relayed:
        return '✓ Relayed';
      case MessageStatus.delivered:
        return '✓✓ Delivered';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(message.createdAt);
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
                if (isOutgoing) ...[
                  const SizedBox(width: 6),
                  Text(_statusLabel,
                      style: const TextStyle(color: AppColors.primaryGreen, fontSize: 11)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
