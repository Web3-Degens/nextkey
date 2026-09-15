/// Finding what was left for you, and opening it.
///
/// The whole of the recipient's side, and it is short on purpose. For a name
/// that holds a secret:
///
///   1. read `nextkey.eph`      — the one ephemeral public key for that secret
///   2. one scalar multiplication with your identity key yields two things:
///      the address `nextkey.g2.<tag>` your grant lives at, and the key that
///      opens it. Neither is derivable from the other, so nobody watching the
///      chain can tell that the address belongs to you.
///   3. read that record, unwrap the content key
///   4. read `nextkey.secret`, decrypt with it, strip the padding
///
/// Nothing here writes, and nothing here needs a wallet. The read receipt in
/// step 5 of the site does need one — it is a record on chain — so this app
/// computes the address and hands it over rather than pretending it can write
/// it.
library;

import 'dart:convert';

import 'crypto.dart';
import 'ens_rpc.dart';
import 'identity.dart';

enum OpenOutcome {
  opened,
  noEphemeralKey,
  noGrantForYou,
  noSecretRecord,
  couldNotDecrypt,
  lookupFailed,
}

class OpenedSecret {
  const OpenedSecret({
    required this.outcome,
    required this.name,
    this.text,
    this.recipientId,
    this.ackRecordKey,
    this.grantRecordKey,
    this.detail,
  });

  final OpenOutcome outcome;
  final String name;
  final String? text;

  /// Only set when the name publishes a key but is handing nothing over right
  /// now. It answers a different question than "is there something for me" —
  /// whether this name could receive at all — and it is also the one read that
  /// exercises the reader against a record that is actually set.
  final String? recipientId;

  /// Where a read receipt would go, if the person chooses to leave one. It is
  /// a record on chain, so it costs privacy — it shows *when* the secret was
  /// read — and this app only ever shows the address.
  final String? ackRecordKey;
  final String? grantRecordKey;
  final String? detail;

  bool get isAboutTheName => outcome != OpenOutcome.lookupFailed;
}

class Inbox {
  Inbox({required this.reader});

  final EnsReader reader;

  /// Is there something on this name addressed to this identity? Answers
  /// without decrypting anything, so a list of watched names can be checked
  /// cheaply.
  Future<OpenedSecret> peek(String name, Identity me) => _read(name, me, open: false);

  Future<OpenedSecret> open(String name, Identity me) => _read(name, me, open: true);

  Future<OpenedSecret> _read(String name, Identity me, {required bool open}) async {
    final eph = await reader.text(name, NkRecords.eph);
    if (eph.failed) {
      return OpenedSecret(
        outcome: OpenOutcome.lookupFailed,
        name: name,
        detail: 'The node did not answer, so this says nothing about the name. '
            '${eph.error ?? ''}',
      );
    }
    if (!eph.present) {
      // Nothing is being handed over on this name. Before saying so, read the
      // one record that is usually set — the published key — because "this
      // name cannot receive at all" and "this name is ready but holds nothing"
      // are different facts, and a screen that spells them the same way
      // teaches the reader something untrue.
      final pub = await reader.text(name, NkRecords.pubkey);
      if (pub.failed) {
        return OpenedSecret(
          outcome: OpenOutcome.lookupFailed,
          name: name,
          detail: pub.error,
        );
      }
      String? id;
      if (pub.present) {
        try {
          final key = un64(pub.value!);
          if (key.length == 32) id = await nextkeyId(key);
        } catch (_) {
          // A name may publish anything under that record. Something that is
          // not a 32-byte key has no ID, and inventing one would put a
          // checkable-looking identifier under a value that identifies nobody.
        }
      }
      return OpenedSecret(
        outcome: OpenOutcome.noEphemeralKey,
        name: name,
        recipientId: id,
      );
    }

    final ephPublic = un64(eph.value!);
    final where = await locateGrant(
      ephPublic: ephPublic,
      mySecret: me.secret,
      myPublic: me.publicKey,
    );

    final grant = await reader.text(name, where.recordKey);
    if (grant.failed) {
      return OpenedSecret(
        outcome: OpenOutcome.lookupFailed,
        name: name,
        detail: grant.error,
      );
    }
    if (!grant.present) {
      // Not "there is nothing here" — there may be a dozen grants on this name.
      // It is that none of them is at the address only you and the sender can
      // compute.
      return OpenedSecret(
        outcome: OpenOutcome.noGrantForYou,
        name: name,
        grantRecordKey: where.recordKey,
      );
    }
    if (!open) {
      return OpenedSecret(
        outcome: OpenOutcome.opened,
        name: name,
        grantRecordKey: where.recordKey,
        ackRecordKey: where.ackKey,
      );
    }

    final sealed = await reader.text(name, NkRecords.secret);
    if (sealed.failed) {
      return OpenedSecret(
          outcome: OpenOutcome.lookupFailed, name: name, detail: sealed.error);
    }
    if (!sealed.present) {
      return OpenedSecret(outcome: OpenOutcome.noSecretRecord, name: name);
    }

    try {
      final contentKey = await openGrant(
        jsonDecode(grant.value!) as Map<String, dynamic>,
        where,
      );
      final text = unpadSecret(await unseal(
        jsonDecode(sealed.value!) as Map<String, dynamic>,
        contentKey,
      ));
      return OpenedSecret(
        outcome: OpenOutcome.opened,
        name: name,
        text: text,
        grantRecordKey: where.recordKey,
        ackRecordKey: where.ackKey,
      );
    } catch (e) {
      // The grant is at the right address but does not open: a truncated
      // record, a record written by hand, or a key that is not the one it was
      // sealed to. None of those is "nothing was sent".
      return OpenedSecret(
        outcome: OpenOutcome.couldNotDecrypt,
        name: name,
        grantRecordKey: where.recordKey,
        detail: '$e',
      );
    }
  }
}
