/// The wrapping rule, on Android.
///
/// This file is the third statement of a construction that already exists
/// twice: `scripts/nextkey-core.mjs` for Node and `web/src/nk-crypto.mjs` for
/// the browser. The three must agree byte for byte, or a grant written on the
/// site would be unopenable on the phone and nobody would find out until
/// somebody needed it.
///
/// The arithmetic is unchanged — X25519, HKDF-SHA256 with the same salts and
/// info strings, AES-256-GCM. Only the spelling is Dart. `test/crypto_test.dart`
/// checks it against vectors generated from the JavaScript construction, which
/// is the only reason this file may be trusted at all.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// ─── Bytes, said once ───────────────────────────────────────────────────────

Uint8List un64(String s) => base64.decode(base64.normalize(s.trim()));
String b64(List<int> bytes) => base64.encode(bytes);

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String s) {
  final h = s.startsWith('0x') ? s.substring(2) : s;
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _cat(List<int> a, List<int> b) =>
    Uint8List.fromList(<int>[...a, ...b]);

// ─── The record names ───────────────────────────────────────────────────────

class NkRecords {
  static const pubkey = 'nextkey.pubkey';
  static const eph = 'nextkey.eph';
  static const ephSealed = 'nextkey.eph.sealed';
  static const secret = 'nextkey.secret';
}

const _infoEph = 'nextkey/v2/eph';
const _infoIdentity = 'nextkey/v2/identity';
const _infoWrap = 'nextkey/v2/wrap';
const _infoTag = 'nextkey/v2/tag';
const _infoSeal = 'nextkey/v2/eph-seal';
const _infoAck = 'nextkey/v2/ack';

// ─── Primitives ─────────────────────────────────────────────────────────────

final _x25519 = X25519();
final _sha256 = Sha256();

Future<Uint8List> sha256Bytes(List<int> input) async =>
    Uint8List.fromList((await _sha256.hash(input)).bytes);

/// HKDF-SHA256 in the argument order the JavaScript uses: `hkdf(hash, ikm,
/// salt, info, length)`. The `nonce` of `package:cryptography` is the salt.
Future<Uint8List> hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  int length = 32,
}) async {
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: length);
  final key = await hkdf.deriveKey(
    secretKey: SecretKey(ikm),
    nonce: salt,
    info: info,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// The X25519 public key for a 32-byte secret.
Future<Uint8List> publicKeyOf(List<int> secret) async {
  final pair = await _x25519.newKeyPairFromSeed(secret);
  final pub = await pair.extractPublicKey();
  return Uint8List.fromList(pub.bytes);
}

/// The raw ECDH output — not a key on its own, always HKDF'd before use.
Future<Uint8List> sharedSecret(List<int> secret, List<int> peerPublic) async {
  final pair = await _x25519.newKeyPairFromSeed(secret);
  final shared = await _x25519.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519),
  );
  return Uint8List.fromList(await shared.extractBytes());
}

/// AES-256-GCM, with the tag appended to the ciphertext — the shape WebCrypto
/// produces, and therefore the shape every NextKey record already holds.
Future<Map<String, String>> seal(List<int> key, String plaintext) async {
  final aes = AesGcm.with256bits();
  final nonce = aes.newNonce();
  final box = await aes.encrypt(
    utf8.encode(plaintext),
    secretKey: SecretKey(key),
    nonce: nonce,
  );
  return {
    'iv': b64(nonce),
    'ct': b64(_cat(box.cipherText, box.mac.bytes)),
  };
}

Future<String> unseal(Map<String, dynamic> record, List<int> key) async {
  final aes = AesGcm.with256bits();
  final iv = un64(record['iv'] as String);
  final joined = un64(record['ct'] as String);
  if (joined.length < 16) {
    throw const FormatException('ciphertext too short to hold a GCM tag');
  }
  final box = SecretBox(
    joined.sublist(0, joined.length - 16),
    nonce: iv,
    mac: Mac(joined.sublist(joined.length - 16)),
  );
  return utf8.decode(await aes.decrypt(box, secretKey: SecretKey(key)));
}

// ─── The two derived keys ───────────────────────────────────────────────────

/// The message a wallet signs to derive the identity key. Byte-identical to
/// `identityMessage()` in `web/src/nk-crypto.mjs`, line breaks included: a
/// stray character derives a different key, and the failure surfaces only as a
/// grant nobody can open.
String identityMessage() => [
      'NextKey — derive your identity key',
      '',
      'version: 2',
      '',
      'This signature is not a transaction. It moves nothing, approves nothing and',
      'costs nothing. It derives the key other people encrypt to when they send you',
      'a secret — the same key every time, from this wallet alone, so there is no',
      'file to keep and nothing to lose. Sign it only on a NextKey page you opened',
      'yourself, and never because someone asked you to.',
    ].join('\n');

String ephMessage(String name) => [
      'NextKey — derive the ephemeral key for a name',
      '',
      'name: $name',
      'version: 2',
      '',
      'This signature is not a transaction. It moves nothing and approves nothing.',
      'It derives the key that addresses every grant on this name, so treat it as',
      'you would the key itself: sign it only on a NextKey page you opened',
      'yourself, and never because someone asked you to.',
    ].join('\n');

Future<Uint8List> identitySecretFromSignature(String signature) => hkdfSha256(
      ikm: unhex(signature),
      salt: utf8.encode(_infoIdentity),
      info: utf8.encode('identity'),
    );

Future<Uint8List> ephSecretFromSignature(String signature, String name) =>
    hkdfSha256(
      ikm: unhex(signature),
      salt: utf8.encode(_infoEph),
      info: utf8.encode(name),
    );

// ─── Grants, v2 ─────────────────────────────────────────────────────────────

Future<Uint8List> wrapKeyV2(
        List<int> shared, List<int> ephPub, List<int> recipientPub) =>
    hkdfSha256(
      ikm: shared,
      salt: _cat(ephPub, recipientPub),
      info: utf8.encode(_infoWrap),
    );

Future<String> grantRecordKey(
    List<int> shared, List<int> ephPub, List<int> recipientPub) async {
  final tag = await hkdfSha256(
    ikm: shared,
    salt: _cat(ephPub, recipientPub),
    info: utf8.encode(_infoTag),
    length: 16,
  );
  return 'nextkey.g2.${hex(tag)}';
}

Future<String> ackRecordKey(
    List<int> shared, List<int> ephPub, List<int> recipientPub) async {
  final tag = await hkdfSha256(
    ikm: shared,
    salt: _cat(ephPub, recipientPub),
    info: utf8.encode(_infoAck),
    length: 16,
  );
  return 'nextkey.a2.${hex(tag)}';
}

/// Where the grant for me lives on this name, and the key that opens it.
///
/// One scalar multiplication yields both, which is the whole shape of v2: the
/// address is not derivable from the key, nor the key from the address, so
/// neither can be computed by somebody watching the chain.
class GrantLocation {
  const GrantLocation({required this.recordKey, required this.kek, required this.ackKey});
  final String recordKey;
  final Uint8List kek;
  final String ackKey;
}

Future<GrantLocation> locateGrant({
  required List<int> ephPublic,
  required List<int> mySecret,
  required List<int> myPublic,
}) async {
  final shared = await sharedSecret(mySecret, ephPublic);
  return GrantLocation(
    recordKey: await grantRecordKey(shared, ephPublic, myPublic),
    kek: await wrapKeyV2(shared, ephPublic, myPublic),
    ackKey: await ackRecordKey(shared, ephPublic, myPublic),
  );
}

/// The content key inside a grant record.
Future<Uint8List> openGrant(
        Map<String, dynamic> grant, GrantLocation where) async =>
    un64(await unseal(grant, where.kek));

/// The ephemeral secret a name keeps for itself, sealed to its owner.
Future<Uint8List> openEphSecret(
  Map<String, dynamic> record,
  List<int> mySecret,
  List<int> myPublic,
) async {
  final wPub = un64(record['epk'] as String);
  final kek = await hkdfSha256(
    ikm: await sharedSecret(mySecret, wPub),
    salt: _cat(wPub, myPublic),
    info: utf8.encode(_infoSeal),
  );
  return un64(await unseal(record, kek));
}

// ─── Padding ────────────────────────────────────────────────────────────────
//
// AES-GCM does not pad, so the ciphertext length is the plaintext length and
// the ciphertext is a public record. Without this, anybody could tell a
// twelve-word phrase from a two-paragraph message without decrypting either.

const padBlock = 256;

String padSecret(String text) {
  final n = utf8.encode(text).length;
  final to = ((n + 1) / padBlock).ceil() * padBlock;
  return text + ' ' * (to - n);
}

String unpadSecret(String text) => text.replaceAll(RegExp(r' +$'), '');

// ─── The NextKey ID ─────────────────────────────────────────────────────────
//
// What a person is shown instead of their key: NK-9F3KD-2M0RQ-7XB4T.
//
// Derived, never issued — the same key gives the same ID on any machine, and
// nothing is written anywhere for it. Crockford's Base32 (no I, L, O or U), 70
// bits of a SHA-256 over the key plus one position-weighted check symbol, which
// catches the single mistyped and the single transposed character. It is a
// presentation of the key, not a second identifier: anyone verifying rather
// than reading compares the key.

const _b32 = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

String _checkSymbol(List<int> symbols) {
  var acc = 0;
  for (var i = 0; i < symbols.length; i++) {
    acc += symbols[i] * (i + 1);
  }
  return _b32[acc % 32];
}

Future<String> nextkeyId(List<int> publicKey) async {
  final h = await sha256Bytes(publicKey);
  var bits = BigInt.zero;
  for (var i = 0; i < 9; i++) {
    bits = (bits << 8) | BigInt.from(h[i]);
  }
  bits >>= 2; // 72 bits read, 70 used
  final symbols = List<int>.filled(14, 0);
  for (var i = 13; i >= 0; i--) {
    symbols[i] = ((bits >> (5 * (13 - i))) & BigInt.from(31)).toInt();
  }
  final s = symbols.map((v) => _b32[v]).join() + _checkSymbol(symbols);
  return 'NK-${s.substring(0, 5)}-${s.substring(5, 10)}-${s.substring(10, 15)}';
}

/// Well-formed — and only that. Never that anybody holds it, and never that a
/// name publishes the key it came from. The name says `looksLike` for a reason
/// and every caller has to keep meaning it.
bool looksLikeNextkeyId(String s) {
  final raw = s
      .trim()
      .toUpperCase()
      .replaceFirst(RegExp(r'^NK-'), '')
      .replaceAll('-', '');
  if (!RegExp(r'^[0-9A-HJKMNP-TV-Z]{15}$').hasMatch(raw)) return false;
  final symbols = raw.substring(0, 14).split('').map(_b32.indexOf).toList();
  return _checkSymbol(symbols) == raw[14];
}

/// A name this app is willing to put in front of a resolver — the same narrow
/// rule the API applies, refusing uppercase and unicode rather than
/// normalising, so that the app and the resolver cannot end up meaning
/// different names.
final RegExp ensName = RegExp(r'^[a-z0-9-]{1,63}(\.[a-z0-9-]{1,63}){1,4}$');
