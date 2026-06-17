import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../models/contact.dart';
import '../models/message.dart';

class ConversationTile extends StatelessWidget {
  final Contact contact;
  final LettalkMessage lastMessage;
  final bool isOutgoing;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.contact,
    required this.lastMessage,
    required this.isOutgoing,
    required this.onTap,
  });

  String get _statusGlyph {
    switch (lastMessage.status) {
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
    final time = DateTime.fromMillisecondsSinceEpoch(lastMessage.createdAt);
    final timeLabel = DateFormat.jm().format(time);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.card,
        child: Text(
          contact.username.isNotEmpty ? contact.username[0].toUpperCase() : '?',
          style: const TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(contact.username, style: const TextStyle(color: AppColors.textPrimary)),
      subtitle: Text(
        '[encrypted message]',
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
          if (isOutgoing)
            Text(_statusGlyph,
                style: const TextStyle(color: AppColors.primaryGreen, fontSize: 11)),
        ],
      ),
    );
  }
}
