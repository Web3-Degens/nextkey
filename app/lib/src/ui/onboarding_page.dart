import 'package:flutter/material.dart';

import '../nk/crypto.dart';
import '../nk/identity.dart';
import 'scan_page.dart';

/// Getting the identity key onto the phone.
///
/// Two ways in, and the difference between them is stated rather than hidden.
/// Pairing from the site derives the key from the wallet signature, exactly as
/// the site does, and hands over the derived bytes; the wallet stays the
/// backup. Typing a key in by hand is for somebody who already has one.
///
/// There is no third way where the app makes up a key of its own. That would
/// create a brand-new thing to guard, which is the design the project already
/// rejected once and for good reasons: its loss costs every secret ever sent.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.store, required this.onDone});

  final IdentityStore store;
  final VoidCallback onDone;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  String? _error;
  bool _busy = false;

  Future<void> _accept(PairingPayload payload) async {
    setState(() => _busy = true);
    try {
      await widget.store.save(payload.secret);
      widget.onDone();
    } catch (e) {
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _scan() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScanPage(
          title: 'Schlüssel koppeln',
          hint: 'Öffne nextkey.li/demo/id am Rechner und zeige den Kopplungs-Code.',
        ),
      ),
    );
    if (result == null) return;
    final payload = PairingPayload.tryParse(result);
    if (payload == null) {
      setState(() => _error =
          'Das ist kein NextKey-Kopplungs-Code. Erwartet wird nextkey://identity/v2?sk=…');
      return;
    }
    await _accept(payload);
  }

  Future<void> _paste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Schlüssel eingeben'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Identitätsschlüssel (Base64, 32 Bytes)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Übernehmen')),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      final bytes = un64(text);
      if (bytes.length != 32) {
        setState(() => _error =
            'Ein Identitätsschlüssel ist 32 Bytes lang, dieser ${bytes.length}.');
        return;
      }
      await _accept(PairingPayload(bytes));
    } catch (_) {
      setState(() => _error = 'Das liess sich nicht als Base64 lesen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Icon(Icons.hexagon_outlined,
                  size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text('NextKey', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Ein Geheimnis übergeben, ohne die Kontrolle zu übergeben.',
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Was diese App hält',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text(
                        'Genau einen Schlüssel: den, mit dem andere dir etwas '
                        'verschlüsseln. Er liegt im Android-Keystore, verlässt '
                        'das Gerät nicht und steht in keinem Backup, das wir '
                        'lesen können. Diese App hält kein Geld, unterschreibt '
                        'nichts und sendet nichts an uns.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Der Schlüssel wird aus deiner Wallet-Signatur '
                        'abgeleitet, nicht erfunden. Geht das Gerät verloren, '
                        'leitest du ihn auf nextkey.li erneut ab — es gibt '
                        'nichts zu sichern.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Mit nextkey.li koppeln'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _busy ? null : _paste,
                child: const Text('Schlüssel von Hand eingeben'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
