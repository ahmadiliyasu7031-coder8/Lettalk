import 'package:flutter/material.dart';

import '../core/constants.dart';

class MessageStatusScreen extends StatelessWidget {
  const MessageStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Message Status Explained')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _StatusLegendCard(
            glyph: '✓',
            color: AppColors.textSecondary,
            title: 'Sent',
            description:
                'Your message has been encrypted and handed to the Uranium Network on your device. It is waiting for a nearby device to relay it onward.',
          ),
          SizedBox(height: 16),
          _StatusLegendCard(
            glyph: '✓',
            color: AppColors.primaryGreen,
            title: 'Relayed',
            description:
                'At least one other Lettalk device has picked up your message and is carrying it toward the recipient, hopping device to device.',
          ),
          SizedBox(height: 16),
          _StatusLegendCard(
            glyph: '✓✓',
            color: AppColors.primaryGreen,
            title: 'Delivered',
            description:
                'The recipient\'s device has received and decrypted your message. Delivery is confirmed.',
          ),
          SizedBox(height: 16),
          _StatusLegendCard(
            glyph: '⊘',
            color: AppColors.statusBad,
            title: 'Kill Signal',
            description:
                'Once a message is delivered, your device automatically broadcasts a Kill Signal that travels the same mesh paths, instructing every device still carrying a copy to delete it. This happens silently in the background — you never see it.',
          ),
        ],
      ),
    );
  }
}

class _StatusLegendCard extends StatelessWidget {
  final String glyph;
  final Color color;
  final String title;
  final String description;

  const _StatusLegendCard({
    required this.glyph,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              glyph,
              style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                Text(description, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
