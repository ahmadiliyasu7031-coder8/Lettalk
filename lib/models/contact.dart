class Contact {
  final String lettalkId;
  final String username;
  final String? publicKey;
  final int lastSeen;

  Contact({
    required this.lettalkId,
    required this.username,
    this.publicKey,
    required this.lastSeen,
  });

  Map<String, dynamic> toMap() {
    return {
      'lettalk_id': lettalkId,
      'username': username,
      'public_key': publicKey,
      'last_seen': lastSeen,
    };
  }

  factory Contact.fromMap(Map<String, dynamic> map) {
    return Contact(
      lettalkId: map['lettalk_id'] as String,
      username: map['username'] as String? ?? 'Unknown',
      publicKey: map['public_key'] as String?,
      lastSeen: map['last_seen'] as int? ?? 0,
    );
  }

  Contact copyWith({String? username, String? publicKey, int? lastSeen}) {
    return Contact(
      lettalkId: lettalkId,
      username: username ?? this.username,
      publicKey: publicKey ?? this.publicKey,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }
}
