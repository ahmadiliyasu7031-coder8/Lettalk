import 'dart:math';
import 'dart:typed_data';

/// Every packet that goes over the air has one of these types. This is
/// how a single characteristic can multiplex several logical channels
/// (handshake vs. application data vs. acknowledgements) instead of
/// needing one GATT characteristic per purpose.
enum BlePacketType {
  handshake,
  handshakeAck,
  data,
  ack,
  keepalive;

  int get wireValue => index;

  static BlePacketType fromWireValue(int value) {
    if (value < 0 || value >= BlePacketType.values.length) {
      throw FormatException('Unknown BlePacketType wire value: $value');
    }
    return BlePacketType.values[value];
  }
}

/// Binary wire format for every BLE packet (brief item 7):
///
///   [1 byte]  packet type
///   [8 bytes] packet id            (uint64, big-endian)
///   [1 byte]  sender id length     (N1)
///   [N1]      sender id (UTF-8)
///   [1 byte]  receiver id length   (N2)
///   [N2]      receiver id (UTF-8)
///   [1 byte]  fragment index
///   [1 byte]  is-last-fragment flag (0/1)
///   [4 bytes] payload length       (uint32, big-endian)
///   [payload]
///   [4 bytes] CRC32 (big-endian) over every byte above
///
/// Sender/receiver ids here are BLE-layer Device IDs (see
/// SettingsRepository.getOrCreateLocalDeviceId), not application-level
/// Lettalk IDs — those live one layer up, inside the JSON payload once
/// the Uranium Protocol takes over.
class BlePacket {
  final BlePacketType type;
  final int packetId;
  final String senderId;
  final String receiverId;
  final int fragmentIndex;
  final bool isLastFragment;
  final Uint8List payload;

  BlePacket({
    required this.type,
    required this.packetId,
    required this.senderId,
    required this.receiverId,
    required this.fragmentIndex,
    required this.isLastFragment,
    required this.payload,
  });

  Uint8List encode() {
    final senderUtf8 = _utf8(senderId);
    final receiverBytes = _utf8(receiverId);

    if (senderUtf8.length > 255 || receiverBytes.length > 255) {
      throw ArgumentError('sender/receiver id too long to encode (max 255 bytes)');
    }

    final builder = BytesBuilder();
    builder.addByte(type.wireValue);
    builder.add(_uint64(packetId));
    builder.addByte(senderUtf8.length);
    builder.add(senderUtf8);
    builder.addByte(receiverBytes.length);
    builder.add(receiverBytes);
    builder.addByte(fragmentIndex & 0xFF);
    builder.addByte(isLastFragment ? 1 : 0);
    builder.add(_uint32(payload.length));
    builder.add(payload);

    final withoutCrc = builder.toBytes();
    final crc = _crc32(withoutCrc);

    final full = BytesBuilder();
    full.add(withoutCrc);
    full.add(_uint32(crc));
    return full.toBytes();
  }

  /// Returns null if the packet is malformed or fails its CRC check —
  /// callers should treat that as "corrupted packet, drop it" (brief
  /// item 7's whole reason for existing).
  static BlePacket? decode(Uint8List bytes) {
    try {
      if (bytes.length < 1 + 8 + 1 + 1 + 1 + 1 + 4 + 4) return null;
      var offset = 0;

      final type = BlePacketType.fromWireValue(bytes[offset]);
      offset += 1;

      final packetId = _readUint64(bytes, offset);
      offset += 8;

      final senderLen = bytes[offset];
      offset += 1;
      final senderId = String.fromCharCodes(bytes.sublist(offset, offset + senderLen));
      offset += senderLen;

      final receiverLen = bytes[offset];
      offset += 1;
      final receiverId = String.fromCharCodes(bytes.sublist(offset, offset + receiverLen));
      offset += receiverLen;

      final fragmentIndex = bytes[offset];
      offset += 1;

      final isLastFragment = bytes[offset] == 1;
      offset += 1;

      final payloadLength = _readUint32(bytes, offset);
      offset += 4;

      if (offset + payloadLength + 4 > bytes.length) return null;
      final payload = Uint8List.fromList(bytes.sublist(offset, offset + payloadLength));
      offset += payloadLength;

      final expectedCrc = _readUint32(bytes, offset);
      final actualCrc = _crc32(bytes.sublist(0, offset));
      if (expectedCrc != actualCrc) return null; // corrupted packet

      return BlePacket(
        type: type,
        packetId: packetId,
        senderId: senderId,
        receiverId: receiverId,
        fragmentIndex: fragmentIndex,
        isLastFragment: isLastFragment,
        payload: payload,
      );
    } catch (_) {
      return null; // malformed — never let a bad packet crash the BLE stack
    }
  }

  static Uint8List _utf8(String s) => Uint8List.fromList(_utf8Encode(s));

  static List<int> _utf8Encode(String s) {
    // Avoid pulling in dart:convert's Utf8Encoder object churn for
    // every tiny packet; codeUnits is sufficient since ids are always
    // generated as ASCII (UUIDs / LTK-XXXX-XXXX), and this stays
    // correct for arbitrary UTF-16 strings too via the encoder below.
    return const Utf8EncoderShim().convert(s);
  }

  static Uint8List _uint64(int value) {
    final b = ByteData(8);
    b.setUint32(0, (value >> 32) & 0xFFFFFFFF, Endian.big);
    b.setUint32(4, value & 0xFFFFFFFF, Endian.big);
    return b.buffer.asUint8List();
  }

  static int _readUint64(Uint8List bytes, int offset) {
    final b = ByteData.sublistView(bytes, offset, offset + 8);
    final high = b.getUint32(0, Endian.big);
    final low = b.getUint32(4, Endian.big);
    return (high << 32) | low;
  }

  static Uint8List _uint32(int value) {
    final b = ByteData(4);
    b.setUint32(0, value, Endian.big);
    return b.buffer.asUint8List();
  }

  static int _readUint32(Uint8List bytes, int offset) {
    return ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);
  }
}

/// Minimal UTF-8 encoder so this file has zero imports beyond
/// dart:typed_data/dart:math — keeps the packet format usable from
/// anywhere (including isolate entry points) without dragging in
/// dart:convert's larger surface just for id strings.
class Utf8EncoderShim {
  const Utf8EncoderShim();

  List<int> convert(String input) {
    final bytes = <int>[];
    for (final rune in input.runes) {
      if (rune < 0x80) {
        bytes.add(rune);
      } else if (rune < 0x800) {
        bytes.add(0xC0 | (rune >> 6));
        bytes.add(0x80 | (rune & 0x3F));
      } else if (rune < 0x10000) {
        bytes.add(0xE0 | (rune >> 12));
        bytes.add(0x80 | ((rune >> 6) & 0x3F));
        bytes.add(0x80 | (rune & 0x3F));
      } else {
        bytes.add(0xF0 | (rune >> 18));
        bytes.add(0x80 | ((rune >> 12) & 0x3F));
        bytes.add(0x80 | ((rune >> 6) & 0x3F));
        bytes.add(0x80 | (rune & 0x3F));
      }
    }
    return bytes;
  }
}

// ---------------------------------------------------------------------
// CRC-32 (IEEE 802.3), standard table-based implementation. Pure Dart,
// no dependency — this is the "Checksum/CRC" field from brief item 7,
// used to detect corrupted packets before they're ever parsed as JSON.
// ---------------------------------------------------------------------

final List<int> _crcTable = _buildCrcTable();

List<int> _buildCrcTable() {
  final table = List<int>.filled(256, 0);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    table[n] = c;
  }
  return table;
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Splits [payload] into BLE-MTU-sized [BlePacket]s (brief item 6: Encode
/// -> Split into BLE MTU size -> Send -> Wait ACK -> Next packet).
/// Packet ids are randomly seeded then incremented per fragment, which is
/// enough uniqueness for duplicate-detection purposes (brief item 8)
/// without needing a distributed id-allocation scheme.
List<BlePacket> fragmentPayload({
  required BlePacketType type,
  required String senderId,
  required String receiverId,
  required Uint8List payload,
  int mtu = 180,
}) {
  // Reserve room for the fixed header so each encoded packet — not just
  // its payload — fits within [mtu].
  final headerOverhead = 1 + 8 + 1 + senderId.length + 1 + receiverId.length + 1 + 1 + 4 + 4;
  final chunkSize = max(1, mtu - headerOverhead);

  final basePacketId = _randomPacketIdBase();
  final packets = <BlePacket>[];

  if (payload.isEmpty) {
    packets.add(BlePacket(
      type: type,
      packetId: basePacketId,
      senderId: senderId,
      receiverId: receiverId,
      fragmentIndex: 0,
      isLastFragment: true,
      payload: payload,
    ));
    return packets;
  }

  var index = 0;
  for (var offset = 0; offset < payload.length; offset += chunkSize) {
    final end = min(offset + chunkSize, payload.length);
    final isLast = end == payload.length;
    packets.add(BlePacket(
      type: type,
      packetId: basePacketId + index,
      senderId: senderId,
      receiverId: receiverId,
      fragmentIndex: index,
      isLastFragment: isLast,
      payload: Uint8List.fromList(payload.sublist(offset, end)),
    ));
    index++;
  }
  return packets;
}

int _randomPacketIdBase() {
  final rand = Random();
  // High bits: current time in ms (keeps ids roughly monotonic and
  // globally distinct across devices); low bits: random, to avoid
  // collisions between two devices that happen to send at the same ms.
  final now = DateTime.now().millisecondsSinceEpoch & 0xFFFFFFF; // 28 bits
  final rnd = rand.nextInt(1 << 20); // 20 bits
  return (now << 20) | rnd;
}
