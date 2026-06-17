import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

/// Generates the permanent Lettalk ID (format LTK-XXXX-XXXX) from a
/// UUID hash on first launch. This ID never changes and is never sent
/// to any server — it only ever exists on-device and inside messages
/// the user explicitly shares (QR code / manual entry).
class IdGenerator {
  static const _uuid = Uuid();
  static const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  /// Permanent identity ID: LTK-XXXX-XXXX
  static String generateLettalkId() {
    final rawUuid = _uuid.v4();
    final hash = sha256.convert(utf8.encode(rawUuid)).toString();
    final segment1 = _toBase36Segment(hash.substring(0, 8));
    final segment2 = _toBase36Segment(hash.substring(8, 16));
    return 'LTK-$segment1-$segment2';
  }

  static String _toBase36Segment(String hexChunk) {
    final value = BigInt.parse(hexChunk, radix: 16);
    var n = value;
    final buffer = StringBuffer();
    final base = BigInt.from(_alphabet.length);
    for (var i = 0; i < 4; i++) {
      final rem = (n % base).toInt();
      buffer.write(_alphabet[rem]);
      n = n ~/ base;
    }
    return buffer.toString();
  }

  /// Unique message ID, used for both regular messages and Kill Signals.
  static String generateMessageId() {
    return 'MSG-${_uuid.v4().replaceAll('-', '').substring(0, 12).toUpperCase()}';
  }

  static bool isValidLettalkId(String id) {
    final pattern = RegExp(r'^LTK-[0-9A-Z]{4}-[0-9A-Z]{4}$');
    return pattern.hasMatch(id.trim().toUpperCase());
  }
}

/// Lightweight pseudo-random helper used for things like jittering
/// scan timing so devices in a crowd don't all wake up in lockstep.
int jitterMillis(int baseMillis, {int spreadMillis = 5000}) {
  final rand = Random();
  return baseMillis + rand.nextInt(spreadMillis);
}
