/// Wire format for the QR code shown on the Profile screen and read by
/// the scanner on the New Message screen. A bare Lettalk ID alone isn't
/// enough to message someone new — since there is no key server, the
/// public key has to travel with the ID the first time two people connect.
///
/// Format: LTK-QR-1|<lettalkId>|<username>|<publicKeyBase64>
class QrPayload {
  final String lettalkId;
  final String username;
  final String publicKey;

  QrPayload({required this.lettalkId, required this.username, required this.publicKey});

  String encode() => 'LTK-QR-1|$lettalkId|$username|$publicKey';

  static QrPayload? tryDecode(String raw) {
    final parts = raw.trim().split('|');
    if (parts.length != 4 || parts[0] != 'LTK-QR-1') return null;
    return QrPayload(lettalkId: parts[1], username: parts[2], publicKey: parts[3]);
  }
}
