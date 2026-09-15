/// Reading text records off the chain, from the phone, without asking anybody.
///
/// The API in `api.dart` answers for the four fixed NextKey records. A grant
/// does not live at a fixed name: `nextkey.g2.<tag>` is derived from a shared
/// secret, so the address is different for every pairing and no endpoint can
/// enumerate it. Finding your own grant therefore means asking a node for one
/// specific text record — which is what this file does.
///
/// It is deliberately small: `eth_call` against the Universal Resolver, with
/// the four-byte selectors computed from their signatures at run time rather
/// than pasted in as constants. A pasted selector is a value nobody can check
/// by reading, and this file is checked by reading.
///
/// What it does not do: CCIP-read. A name whose resolver answers with
/// `OffchainLookup` reverts here, and the failure is reported as a failure
/// rather than as an empty record — the distinction this project has already
/// got wrong three times.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/keccak.dart';

/// The hackathon deployment. viem ships its own Sepolia Universal Resolver
/// address, and using it queries the production deployment and returns null —
/// no error, no warning. That failure has cost this project a day once already.
const universalResolver = '0xd26f2040d083af1cd2962ba303f4bea0c4faf142';
const sepoliaRpc = 'https://ethereum-sepolia-rpc.publicnode.com';

Uint8List keccak256(List<int> input) {
  final d = KeccakDigest(256);
  return d.process(Uint8List.fromList(input));
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _unhex(String s) {
  final h = s.startsWith('0x') ? s.substring(2) : s;
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _selector(String signature) =>
    Uint8List.sublistView(keccak256(utf8.encode(signature)), 0, 4);

/// ENS namehash. Empty name is 32 zero bytes; every label folds in from the
/// right.
Uint8List namehash(String name) {
  var node = Uint8List(32);
  if (name.isEmpty) return node;
  for (final label in name.split('.').reversed) {
    if (label.isEmpty) continue;
    node = keccak256(<int>[...node, ...keccak256(utf8.encode(label))]);
  }
  return node;
}

/// DNS wire format: each label prefixed with its length, terminated by a zero.
Uint8List dnsEncode(String name) {
  final out = <int>[];
  for (final label in name.split('.')) {
    if (label.isEmpty) continue;
    final bytes = utf8.encode(label);
    if (bytes.length > 63) {
      throw FormatException('label longer than 63 bytes: $label');
    }
    out..add(bytes.length)..addAll(bytes);
  }
  out.add(0);
  return Uint8List.fromList(out);
}

Uint8List _word(int value) {
  final w = Uint8List(32);
  var v = value;
  for (var i = 31; i >= 0 && v > 0; i--) {
    w[i] = v & 0xff;
    v >>= 8;
  }
  return w;
}

Uint8List _padRight(List<int> bytes) {
  final rem = bytes.length % 32;
  return Uint8List.fromList(
      <int>[...bytes, if (rem != 0) ...List<int>.filled(32 - rem, 0)]);
}

int _readWord(Uint8List data, int offset) {
  var v = 0;
  for (var i = offset; i < offset + 32; i++) {
    v = (v << 8) | data[i];
  }
  return v;
}

/// `text(bytes32 node, string key)` — the call the resolver answers.
Uint8List encodeTextCall(String name, String key) {
  final node = namehash(name);
  final keyBytes = utf8.encode(key);
  return Uint8List.fromList(<int>[
    ..._selector('text(bytes32,string)'),
    ...node,
    ..._word(64), // offset to the string
    ..._word(keyBytes.length),
    ..._padRight(keyBytes),
  ]);
}

/// `resolve(bytes name, bytes data)` on the Universal Resolver, which finds the
/// resolver for the name and forwards the inner call.
Uint8List encodeResolveCall(String name, Uint8List innerCall) {
  final dns = dnsEncode(name);
  final dnsPadded = _padRight(dns);
  final dataOffset = 64 + 32 + dnsPadded.length;
  return Uint8List.fromList(<int>[
    ..._selector('resolve(bytes,bytes)'),
    ..._word(64),
    ..._word(dataOffset),
    ..._word(dns.length),
    ...dnsPadded,
    ..._word(innerCall.length),
    ..._padRight(innerCall),
  ]);
}

/// The first return value of `resolve` is `bytes`, in every version of the
/// Universal Resolver this project has met. Later versions append a second and
/// third word; reading only the first head word is what makes this indifferent
/// to which one answered.
Uint8List decodeFirstBytes(Uint8List returnData) {
  if (returnData.isEmpty) return Uint8List(0);
  final offset = _readWord(returnData, 0);
  final length = _readWord(returnData, offset);
  return Uint8List.sublistView(returnData, offset + 32, offset + 32 + length);
}

String decodeString(Uint8List abi) {
  if (abi.isEmpty) return '';
  final offset = _readWord(abi, 0);
  final length = _readWord(abi, offset);
  if (length == 0) return '';
  return utf8.decode(Uint8List.sublistView(abi, offset + 32, offset + 32 + length));
}

/// Three outcomes, deliberately not two: a value, an absence, or a failure to
/// find out. The third is not the second.
class TextRecord {
  const TextRecord.value(this.value)
      : failed = false,
        error = null;
  const TextRecord.absent()
      : value = null,
        failed = false,
        error = null;
  const TextRecord.failed(this.error)
      : value = null,
        failed = true;

  final String? value;
  final bool failed;
  final String? error;

  bool get present => value != null && value!.isNotEmpty;
}

class EnsReader {
  EnsReader({http.Client? client, this.rpc = sepoliaRpc})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String rpc;
  var _id = 0;

  Future<TextRecord> text(String name, String key) async {
    final call = encodeResolveCall(name, encodeTextCall(name, key));
    try {
      final res = await _client
          .post(
            Uri.parse(rpc),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': ++_id,
              'method': 'eth_call',
              'params': [
                {'to': universalResolver, 'data': '0x${_hex(call)}'},
                'latest',
              ],
            }),
          )
          .timeout(const Duration(seconds: 20));

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['error'] != null) {
        // A resolver that reverts is not a name that holds nothing.
        return TextRecord.failed(
            (body['error'] as Map)['message']?.toString() ?? 'the node refused');
      }
      final data = _unhex(body['result'] as String? ?? '0x');
      if (data.isEmpty) return const TextRecord.absent();
      final value = decodeString(decodeFirstBytes(data));
      return value.isEmpty ? const TextRecord.absent() : TextRecord.value(value);
    } catch (e) {
      return TextRecord.failed('$e');
    }
  }

  void close() => _client.close();
}
