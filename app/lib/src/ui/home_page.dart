import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../nk/identity.dart';
import '../theme.dart';

/// What a person is shown instead of their key.
///
/// The ID is the presentation; the key is the thing the arithmetic uses. Both
/// are here, in that order, and the screen says which is which — anyone
/// verifying rather than reading compares the key.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.identity, required this.store});

  final Identity identity;
  final IdentityStore store;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Deine NextKey ID')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: identity.publicKeyBase64,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          SelectableText(
            identity.id,
            textAlign: TextAlign.center,
            style: nkMono.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Abgeleitet, nicht vergeben. Derselbe Schlüssel ergibt überall '
            'dieselbe ID — es gibt kein Register und nichts zu verlieren.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: identity.id));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('ID kopiert')),
                      );
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('ID kopieren'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  // share_plus 10. The `SharePlus.instance.share(ShareParams(…))`
                  // spelling belongs to 11 and later; this project resolves to
                  // 10 because of what the other packages allow.
                  onPressed: () => Share.share(
                    'Meine NextKey ID: ${identity.id}\n'
                    'Schlüssel: ${identity.publicKeyBase64}\n'
                    'https://nextkey.li/demo/send',
                    subject: 'Meine NextKey ID',
                  ),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Teilen'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Der Schlüssel selbst', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SelectableText(identity.publicKeyBase64, style: nkMono),
                  const SizedBox(height: 12),
                  Text(
                    'Öffentlich. Wer prüft statt liest, vergleicht diesen Wert '
                    'und nicht die ID.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Damit dich jemand erreichen kann',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'Dieser Schlüssel muss unter nextkey.pubkey auf deinem '
                    'ENS-Namen stehen. Das Veröffentlichen ist die ganze '
                    'Einwilligung — und es braucht eine Transaktion, also '
                    'passiert es auf nextkey.li und nicht hier.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
