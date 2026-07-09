class Identity {
  final String lettalkId;
  final String username;
  final String encryptedPrivateKey;
  final String publicKey;
  final int createdAt;

  Identity({
    required this.lettalkId,
    required this.username,
    required this.encryptedPrivateKey,
    required this.publicKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'lettalk_id': lettalkId,
      'username': username,
      'private_key': encryptedPrivateKey,
      'public_key': publicKey,
      'created_at': createdAt,
    };
  }

  factory Identity.fromMap(Map<String, dynamic> map) {
    return Identity(
      lettalkId: map['lettalk_id'] as String,
      username: map['username'] as String,
      encryptedPrivateKey: map['private_key'] as String,
      publicKey: map['public_key'] as String,
      createdAt: map['created_at'] as int,
    );
  }

  Identity copyWith({String? username}) {
    return Identity(
      lettalkId: lettalkId,
      username: username ?? this.username,
      encryptedPrivateKey: encryptedPrivateKey,
      publicKey: publicKey,
      createdAt: createdAt,
    );
  }
}

/// Tracks which (message_id) this node has already forwarded, and to
/// how many peers, so the Uranium Protocol never re-forwards the same
/// message to a peer it has already given it to.
class RelayLogEntry {
  final String messageId;
  final int firstSeen;
  final int forwardCount;

  RelayLogEntry({
    required this.messageId,
    required this.firstSeen,
    this.forwardCount = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'first_seen': firstSeen,
      'forward_count': forwardCount,
    };
  }

  factory RelayLogEntry.fromMap(Map<String, dynamic> map) {
    return RelayLogEntry(
      messageId: map['message_id'] as String,
      firstSeen: map['first_seen'] as int,
      forwardCount: map['forward_count'] as int? ?? 0,
    );
  }
}

/// Tracks which peer device IDs a given message_id has already been
/// forwarded to. This is what backs the "never forward the same
/// message_id twice to the same peer" rule.
class RelayPeerRecord {
  final String messageId;
  final String peerDeviceId;
  final int forwardedAt;

  RelayPeerRecord({
    required this.messageId,
    required this.peerDeviceId,
    required this.forwardedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'message_id': messageId,
      'peer_device_id': peerDeviceId,
      'forwarded_at': forwardedAt,
    };
  }

  factory RelayPeerRecord.fromMap(Map<String, dynamic> map) {
    return RelayPeerRecord(
      messageId: map['message_id'] as String,
      peerDeviceId: map['peer_device_id'] as String,
      forwardedAt: map['forwarded_at'] as int,
    );
  }
}
