import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../nk/crypto.dart';
import '../nk/identity.dart';
import '../nk/push.dart';
import '../theme.dart';
import 'scan_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.identity,
    required this.onChanged,
    required this.onPaired,
  });

  final IdentityStore store;
  final Identity identity;
  final VoidCallback onChanged;

  /// A key has just replaced the one that was here. Separate from `onChanged`
  /// because the two want different screens afterwards: removing a key ends on
  /// the onboarding page, pairing one ends on the ID it produced.
  final VoidCallback onPaired;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _push = PushService();
  bool _requireUnlock = true;
  bool _canUnlock = false;
  bool _pushOn = false;

  @override
  void initState() {
    super.initState();
    widget.store.requiresUnlock.then((v) {
      if (mounted) setState(() => _requireUnlock = v);
    });
    widget.store.canUnlock.then((v) {
      if (mounted) setState(() => _canUnlock = v);
    });
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  /// Pair again, without deleting first.
  ///
  /// The only way to scan a second code used to be "remove the key from this
  /// device", which asks somebody to destroy what they have in order to replace
  /// it — and is a genuinely frightening thing to press when you are not yet
  /// sure the new code works. So the scan stands on its own, the old key is
  /// replaced only after the new one has been read and understood, and the
  /// screen says which ID is about to take over.
  Future<void> _pairAgain() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScanPage(
          title: 'Schlüssel koppeln',
          hint: 'Öffne nextkey.li/demo/id am Rechner, decke den '
              'Kopplungs-Code auf und halte die Kamera darauf.',
        ),
      ),
    );
    if (result == null) return;

    final payload = PairingPayload.tryParse(result);
    if (payload == null) {
      _say('Das ist kein NextKey-Kopplungs-Code.');
      return;
    }

    final id = await nextkeyId(await publicKeyOf(payload.secret));
    if (id == widget.identity.id) {
      _say('Derselbe Schlüssel — es hat sich nichts geändert.');
      return;
    }
    if (!mounted) return;

    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schlüssel ersetzen?'),
        content: Text(
          'Dieses Gerät hält dann $id statt ${widget.identity.id}. Was an die '
          'alte ID geschickt wurde, lässt sich hier danach nicht mehr öffnen — '
          'wohl aber wieder, sobald du sie erneut koppelst.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Ersetzen')),
        ],
      ),
    );
    if (sure != true) return;
    if (!await widget.store.unlock(reason: 'Schlüssel ersetzen')) return;

    await widget.store.save(payload.secret);
    _say('Gekoppelt. Das ist jetzt deine ID.');
    widget.onPaired();
  }

  Future<void> _forget() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schlüssel von diesem Gerät entfernen?'),
        content: const Text(
          'Der Schlüssel ist aus deiner Wallet-Signatur abgeleitet, also lässt '
          'er sich auf nextkey.li jederzeit wieder ableiten — hier verschwindet '
          'er dann aber sofort, samt der beobachteten Namen.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Entfernen')),
        ],
      ),
    );
    if (sure != true) return;
    if (!await widget.store.unlock(reason: 'Schlüssel entfernen')) return;
    await widget.store.forget();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SwitchListTile(
            value: _requireUnlock,
            onChanged: _canUnlock
                ? (v) async {
                    await widget.store.setRequiresUnlock(v);
                    setState(() => _requireUnlock = v);
                  }
                : null,
            title: const Text('Vor dem Öffnen entsperren'),
            subtitle: Text(_canUnlock
                ? 'Biometrie oder Geräte-PIN, bevor ein Geheimnis sichtbar wird.'
                : 'Auf diesem Gerät ist weder Biometrie noch eine PIN '
                    'eingerichtet. Der Schlüssel liegt trotzdem im Keystore, '
                    'aber ungeschützter, als er sein sollte.'),
          ),
          SwitchListTile(
            value: _pushOn,
            onChanged: (v) async {
              if (v && !await _push.requestPermission()) return;
              if (v) await _push.start();
              if (mounted) setState(() => _pushOn = v);
            },
            title: const Text('Benachrichtigen, wenn sich etwas ändert'),
            subtitle: const Text(
              'Optional, und es kostet etwas: der Dienst erfährt den Hash der '
              'Namen, die du beobachtest. Er erfährt nie deinen Schlüssel und '
              'nie, welcher Eintrag dir gehört. Die Meldung selbst enthält '
              'keinen Inhalt.',
            ),
          ),
          const Divider(height: 32),
          ListTile(
            title: const Text('Deine NextKey ID'),
            subtitle: SelectableText(widget.identity.id, style: nkMono),
          ),
          const ListTile(
            title: Text('Netzwerk'),
            subtitle: Text('Sepolia — das Testnetz.'),
          ),
          ListTile(
            title: const Text('Was diese App nicht tut'),
            subtitle: const Text(
              'Sie hält kein Geld, unterschreibt keine Transaktion, schreibt '
              'nichts auf die Kette und schickt kein Geheimnis an einen Server. '
              'Veröffentlichen, Senden und Lesebestätigungen brauchen eine '
              'Transaktion und passieren auf nextkey.li.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.open_in_new),
            title: const Text('nextkey.li'),
            onTap: () => launchUrl(Uri.parse('https://nextkey.li/demo/'),
                mode: LaunchMode.externalApplication),
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: const Text('Datenschutz'),
            onTap: () => launchUrl(Uri.parse('https://nextkey.li/privacy'),
                mode: LaunchMode.externalApplication),
          ),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Anderen Schlüssel koppeln'),
            subtitle: const Text(
              'Kopplungs-Code auf nextkey.li/demo/id scannen. Ersetzt den '
              'Schlüssel auf diesem Gerät — erst nach einer Rückfrage.',
            ),
            onTap: _pairAgain,
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text('Schlüssel von diesem Gerät entfernen',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: _forget,
          ),
        ],
      ),
    );
  }
}
