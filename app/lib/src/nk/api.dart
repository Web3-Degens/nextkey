/// The read-only window onto the chain.
///
/// Two ways of learning what a name publishes, and the app keeps both for the
/// same reason the project keeps both: `api.nextkey.li` is a convenience for
/// callers who cannot reach a node, not a component anything depends on. If it
/// is down, or if someone would rather not tell us which name they are looking
/// up, `EnsReader` in `ens_rpc.dart` reads the chain directly and this file is
/// not used at all.
///
/// The two kinds of "no" the API is careful about are carried through here
/// rather than flattened: a name that publishes no key and a node that did not
/// answer are different facts, and a screen that spells them the same way
/// teaches the reader something untrue.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

const nextkeyApiBase = 'https://api.nextkey.li';
const nextkeyNetworkPrefix = '/demo/v1'; // Sepolia. Mainnet is reserved as /v1.

enum LookupOutcome {
  ok,
  notOnThisDeployment,
  noPublishedKey,
  keyNotX25519,
  malformedName,
  upstreamUnavailable,
  networkFailed,
}

class NameLookup {
  const NameLookup({
    required this.outcome,
    this.name,
    this.nextkeyId,
    this.pubkey,
    this.records = const {},
    this.role,
    this.message,
  });

  final LookupOutcome outcome;
  final String? name;
  final String? nextkeyId;
  final String? pubkey;
  final Map<String, String?> records;
  final String? role;
  final String? message;

  bool get receivable => pubkey != null;

  /// Whether this says anything about the name at all. A failed lookup does
  /// not, and the screens must not render it as if it did.
  bool get isAboutTheName =>
      outcome != LookupOutcome.upstreamUnavailable &&
      outcome != LookupOutcome.networkFailed;
}

class NextkeyApi {
  NextkeyApi({http.Client? client, this.base = nextkeyApiBase})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String base;

  Uri _uri(String path) => Uri.parse('$base$nextkeyNetworkPrefix$path');

  Future<NameLookup> lookup(String name, {bool idOnly = false}) async {
    final n = name.trim().toLowerCase();
    http.Response res;
    try {
      res = await _client
          .get(_uri('${idOnly ? '/id' : '/name'}/${Uri.encodeComponent(n)}'))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      return NameLookup(
        outcome: LookupOutcome.networkFailed,
        name: n,
        message: 'The lookup did not complete, so this says nothing about the '
            'name. ($e)',
      );
    }

    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;

    if (res.statusCode == 200) {
      return NameLookup(
        outcome: LookupOutcome.ok,
        name: body['name'] as String?,
        nextkeyId: body['nextkeyId'] as String?,
        pubkey: body['pubkey'] as String? ??
            (body['records'] as Map?)?['nextkey.pubkey'] as String?,
        records: ((body['records'] as Map?) ?? {})
            .map((k, v) => MapEntry(k as String, v as String?)),
        role: body['role'] as String?,
        message: body['note'] as String?,
      );
    }

    final error = (body['error'] as Map?) ?? const {};
    final code = error['code'] as String? ?? 'unknown';
    return NameLookup(
      outcome: switch (code) {
        'not_on_this_deployment' => LookupOutcome.notOnThisDeployment,
        'no_published_key' => LookupOutcome.noPublishedKey,
        'key_not_x25519' => LookupOutcome.keyNotX25519,
        'malformed_name' => LookupOutcome.malformedName,
        'upstream_unavailable' => LookupOutcome.upstreamUnavailable,
        _ => LookupOutcome.networkFailed,
      },
      name: n,
      message: error['message'] as String?,
    );
  }

  Future<bool> health() async {
    try {
      final res =
          await _client.get(_uri('/health')).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void close() => _client.close();
}
