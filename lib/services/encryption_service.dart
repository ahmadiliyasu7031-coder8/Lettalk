import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Implements the encryption model described in the brief:
///   1. X25519 keypair generated on first launch
///   2. Shared secret derived per-contact via X25519 key agreement
///   3. Message content encrypted with AES-256-GCM under that shared secret
///   4. Private key never leaves the device, and is itself encrypted at
///      rest using a device-derived key held in secure storage.
///
/// Relay nodes can read message_id and recipient_id (needed for routing)
/// but never plaintext_content — only the recipient's private key can
/// unlock a given message.
class EncryptionService {
  static final EncryptionService instance = EncryptionService._internal();
  EncryptionService._internal();

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _secureStorage = const FlutterSecureStorage();

  static const _deviceKeyStorageKey = 'lettalk_device_wrap_key_v1';

  /// Generates a brand-new X25519 keypair for first-launch identity setup.
  /// Returns (publicKeyBase64, privateKeyBase64-plaintext) — caller is
  /// responsible for passing the private key through [encryptPrivateKey]
  /// before persisting it.
  Future<({String publicKey, String privateKeyPlain})> generateKeyPair() async {
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
    return (
      publicKey: base64Encode(publicKey.bytes),
      privateKeyPlain: base64Encode(privateKeyBytes),
    );
  }

  /// Wraps the X25519 private key at rest using a device-derived AES key
  /// that itself lives in the platform secure storage (Android Keystore
  /// backed). This satisfies "private_key stored encrypted in SQLite".
  Future<String> encryptPrivateKey(String privateKeyPlainBase64) async {
    final wrapKey = await _getOrCreateDeviceWrapKey();
    final plainBytes = base64Decode(privateKeyPlainBase64);
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: wrapKey,
      nonce: nonce,
    );
    return base64Encode(_packSecretBox(secretBox));
  }

  Future<String> decryptPrivateKey(String encryptedBase64) async {
    final wrapKey = await _getOrCreateDeviceWrapKey();
    final secretBox = _unpackSecretBox(base64Decode(encryptedBase64));
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: wrapKey);
    return base64Encode(plainBytes);
  }

  Future<SecretKey> _getOrCreateDeviceWrapKey() async {
    final existing = await _secureStorage.read(key: _deviceKeyStorageKey);
    if (existing != null) {
      return SecretKey(base64Decode(existing));
    }
    final newKey = await _aesGcm.newSecretKey();
    final bytes = await newKey.extractBytes();
    await _secureStorage.write(key: _deviceKeyStorageKey, value: base64Encode(bytes));
    return newKey;
  }

  /// Derives the shared AES key between this device and a contact using
  /// X25519 key agreement: ECDH(myPrivateKey, theirPublicKey).
  Future<SecretKey> deriveSharedSecret({
    required String myPrivateKeyPlainBase64,
    required String theirPublicKeyBase64,
  }) async {
    final myKeyPair = SimpleKeyPairData(
      base64Decode(myPrivateKeyPlainBase64),
      publicKey: SimplePublicKey(
        // public key is re-derived implicitly by the algorithm during
        // sharedSecretKey(); placeholder bytes are not used for ECDH math.
        Uint8List(32),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );
    final theirPublicKey = SimplePublicKey(
      base64Decode(theirPublicKeyBase64),
      type: KeyPairType.x25519,
    );
    return _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: theirPublicKey,
    );
  }

  /// Encrypts plaintext message content with AES-256-GCM under the
  /// shared secret with the recipient. Output is a single base64 blob
  /// containing nonce + ciphertext + MAC, safe to store as TEXT.
  Future<String> encryptContent({
    required String plaintext,
    required SecretKey sharedSecret,
  }) async {
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: sharedSecret,
      nonce: nonce,
    );
    return base64Encode(_packSecretBox(secretBox));
  }

  Future<String> decryptContent({
    required String encryptedBase64,
    required SecretKey sharedSecret,
  }) async {
    final secretBox = _unpackSecretBox(base64Decode(encryptedBase64));
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedSecret);
    return utf8.decode(plainBytes);
  }

  // --- SecretBox <-> bytes packing: [12-byte nonce][ciphertext][16-byte mac] ---

  Uint8List _packSecretBox(SecretBox box) {
    final out = BytesBuilder();
    out.add(box.nonce);
    out.add(box.cipherText);
    out.add(box.mac.bytes);
    return out.toBytes();
  }

  SecretBox _unpackSecretBox(Uint8List bytes) {
    final nonce = bytes.sublist(0, 12);
    final mac = bytes.sublist(bytes.length - 16);
    final cipherText = bytes.sublist(12, bytes.length - 16);
    return SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
  }
}
