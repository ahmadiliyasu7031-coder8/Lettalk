import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';

/// Generic conversation row — takes plain display values so it can
/// render both a real (encrypted, possibly still-undecrypted) message
/// preview and an outbox "waiting" draft identically.
class ConversationTile extends StatelessWidget {
  final String username;
  final String previewText;
  final String statusLabel;
  final Color statusColor;
  final int createdAt;
  final bool isOutgoing;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.username,
    required this.previewText,
    required this.statusLabel,
    required this.createdAt,
    required this.isOutgoing,
    required this.onTap,
    this.statusColor = AppColors.primaryGreen,
  });

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final timeLabel = DateFormat.jm().format(time);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.card,
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(username, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(
        previewText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(timeLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          if (isOutgoing && statusLabel.isNotEmpty)
            Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11)),
        ],
      ),
    );
  }
}
