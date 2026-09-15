/// The one secret this app holds, and where it is kept.
///
/// On the site the identity key is derived from a wallet signature and never
/// stored: the wallet is the backup, and the key comes back byte for byte on
/// any machine the person can sign from. A phone has no wallet of ours to sign
/// with, so the app keeps the derived key instead — which is a real difference
/// and is stated plainly on the screen that offers it, not buried here.
///
/// Kept in `flutter_secure_storage` with `encryptedSharedPreferences`, whose
/// master key lives in the Android Keystore: the bytes never leave the device,
/// are not in any backup we can read, and are gone when the app is uninstalled.
/// Uninstalling therefore loses nothing that cannot be derived again from the
/// wallet, which is the property worth keeping.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'crypto.dart';

const _kSecret = 'nextkey.identity.secret.v2';
const _kNames = 'nextkey.names';
const _kRequireUnlock = 'nextkey.require.unlock';

/// What a pairing QR carries: `nextkey://identity/v2?sk=<base64url>`.
///
/// It is the private half of an identity key, so the page that shows it says
/// so, and this parser refuses anything that is not exactly 32 bytes rather
/// than storing whatever it was handed.
class PairingPayload {
  const PairingPayload(this.secret);
  final Uint8List secret;

  static PairingPayload? tryParse(String raw) {
    final text = raw.trim();
    Uri? uri;
    try {
      uri = Uri.parse(text);
    } catch (_) {
      return null;
    }
    final isPairing = uri.scheme == 'nextkey' &&
        (uri.host == 'identity' || uri.pathSegments.contains('identity'));
    final encoded = isPairing ? uri.queryParameters['sk'] : null;
    if (encoded == null) return null;
    try {
      final bytes = un64(encoded.replaceAll('-', '+').replaceAll('_', '/'));
      if (bytes.length != 32) return null;
      return PairingPayload(bytes);
    } catch (_) {
      return null;
    }
  }
}

class Identity {
  const Identity({required this.secret, required this.publicKey, required this.id});
  final Uint8List secret;
  final Uint8List publicKey;
  final String id;

  String get publicKeyBase64 => b64(publicKey);
}

class IdentityStore {
  IdentityStore({FlutterSecureStorage? storage, LocalAuthentication? auth})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            ),
        _auth = auth ?? LocalAuthentication();

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  Future<bool> get exists async => await _storage.read(key: _kSecret) != null;

  Future<bool> get requiresUnlock async =>
      (await _storage.read(key: _kRequireUnlock) ?? 'true') == 'true';

  Future<void> setRequiresUnlock(bool value) =>
      _storage.write(key: _kRequireUnlock, value: value ? 'true' : 'false');

  /// Is there anything on this device to unlock with? A phone with no
  /// enrolled biometric and no PIN can still hold a key — the screen says the
  /// protection is weaker rather than refusing to work.
  Future<bool> get canUnlock async {
    try {
      return await _auth.isDeviceSupported() &&
          await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlock({String reason = 'Unlock your NextKey identity'}) async {
    if (!await requiresUnlock) return true;
    if (!await canUnlock) return true;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> save(Uint8List secret) async {
    if (secret.length != 32) {
      throw ArgumentError('an identity secret is 32 bytes, not ${secret.length}');
    }
    await _storage.write(key: _kSecret, value: b64(secret));
  }

  /// Reads the key. Every path that needs the key goes through `unlock` first;
  /// this method does not unlock by itself, so that no screen can quietly use
  /// the key without the gate being visible in its own code.
  Future<Identity?> read() async {
    final stored = await _storage.read(key: _kSecret);
    if (stored == null) return null;
    final secret = un64(stored);
    final pub = await publicKeyOf(secret);
    return Identity(secret: secret, publicKey: pub, id: await nextkeyId(pub));
  }

  Future<void> forget() async {
    await _storage.delete(key: _kSecret);
    await _storage.delete(key: _kNames);
  }

  Future<List<String>> names() async {
    final raw = await _storage.read(key: _kNames);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List).cast<String>();
  }

  Future<void> setNames(List<String> names) =>
      _storage.write(key: _kNames, value: jsonEncode(names));
}
