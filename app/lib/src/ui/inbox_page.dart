import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../nk/crypto.dart';
import '../nk/identity.dart';
import '../nk/inbox.dart';
import '../nk/push.dart';
import '../theme.dart';
import 'scan_page.dart';

/// The names you watch, and what is on them for you.
///
/// "Nothing for you here" and "the node did not answer" never share a line.
/// This project has conflated absence with failure-to-find three times and each
/// time it produced a confident sentence about a world nobody had looked at.
class InboxPage extends StatefulWidget {
  const InboxPage({
    super.key,
    required this.identity,
    required this.store,
    required this.inbox,
  });

  final Identity identity;
  final IdentityStore store;
  final Inbox inbox;

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final _push = PushService();
  List<String> _names = const [];
  final Map<String, OpenedSecret> _state = {};

  /// Which names are being checked right now. A lookup goes to a public node
  /// and can take seconds; without this the card sits there unchanged and the
  /// button looks broken — which is how a working app gets reported as dead.
  final Set<String> _busy = {};
  bool get _checking => _busy.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.store.names().then((n) {
      if (mounted) setState(() => _names = n);
    });
  }

  Future<void> _addName(String raw) async {
    final name = raw.trim().toLowerCase();
    if (!ensName.hasMatch(name)) {
      _say('Kein Name, den dieser Resolver beantwortet: $name');
      return;
    }
    if (_names.contains(name)) return;
    final next = [..._names, name];
    await widget.store.setNames(next);
    try {
      await _push.watch(name);
    } catch (_) {
      // Push is optional. A name is watched locally whether or not the
      // notifier could be reached.
    }
    if (mounted) setState(() => _names = next);
    await _check(name);
  }

  Future<void> _removeName(String name) async {
    final next = _names.where((n) => n != name).toList();
    await widget.store.setNames(next);
    try {
      await _push.unwatch(name);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _names = next;
        _state.remove(name);
      });
    }
  }

  Future<void> _check(String name) async {
    setState(() => _busy.add(name));
    OpenedSecret result;
    try {
      result = await widget.inbox.peek(name, widget.identity);
    } catch (e) {
      // Nothing below this line is allowed to fail silently: an exception that
      // never reaches the screen is indistinguishable from a button that does
      // nothing.
      result = OpenedSecret(
        outcome: OpenOutcome.lookupFailed,
        name: name,
        detail: '$e',
      );
    }
    if (!mounted) return;
    setState(() {
      _state[name] = result;
      _busy.remove(name);
    });
  }

  Future<void> _checkAll() async {
    for (final name in _names) {
      await _check(name);
    }
  }

  Future<void> _open(String name) async {
    if (!await widget.store.unlock(reason: 'Geheimnis auf $name öffnen')) {
      _say('Ohne Entsperren bleibt der Schlüssel liegen.');
      return;
    }
    final result = await widget.inbox.open(name, widget.identity);
    if (!mounted) return;
    setState(() => _state[name] = result);
    if (result.outcome == OpenOutcome.opened && result.text != null) {
      await _showSecret(result);
    }
  }

  Future<void> _showSecret(OpenedSecret result) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(result.text!, style: nkMono),
            const SizedBox(height: 16),
            Text(
              'Eine Lesebestätigung wäre ein zweiter Eintrag auf der Kette — '
              'sie zeigt, wann gelesen wurde, und braucht eine Transaktion. '
              'Diese App schreibt nichts; die Adresse dafür lautet '
              '${result.ackRecordKey ?? '—'}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: result.text!));
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kopieren'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schliessen'),
          ),
        ],
      ),
    );
  }

  void _say(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  Future<void> _promptForName() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Namen beobachten'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'ENS-Name',
            hintText: 'anna.nextkey.eth',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Hinzufügen')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) await _addName(name);
  }

  Future<void> _scanName() async {
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const ScanPage(
          title: 'Namen scannen',
          hint: 'Ein QR-Code mit einem ENS-Namen oder einem nextkey.li-Link.',
        ),
      ),
    );
    if (raw == null) return;
    // A link from the site carries the name in its path; a bare name is itself.
    final candidate = Uri.tryParse(raw.trim());
    final fromPath = candidate?.queryParameters['name'] ??
        candidate?.pathSegments.where((s) => s.contains('.eth')).firstOrNull;
    await _addName(fromPath ?? raw);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Für mich'),
        actions: [
          IconButton(
            onPressed: _checking ? null : _checkAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Alle prüfen',
          ),
          IconButton(
            onPressed: _scanName,
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Namen scannen',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _promptForName,
        icon: const Icon(Icons.add),
        label: const Text('Name'),
      ),
      body: _names.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Noch kein Name', style: theme.textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                    'Trag den ENS-Namen dessen ein, der dir etwas hinterlegt '
                    'hat. Die App rechnet lokal aus, an welcher Adresse dein '
                    'Anteil liegt — diese Adresse kann niemand sonst berechnen, '
                    'auch wir nicht.',
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: _names.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final name = _names[i];
                return _NameCard(
                  name: name,
                  state: _state[name],
                  busy: _busy.contains(name),
                  onCheck: () => _check(name),
                  onOpen: () => _open(name),
                  onRemove: () => _removeName(name),
                );
              },
            ),
    );
  }
}

class _NameCard extends StatelessWidget {
  const _NameCard({
    required this.name,
    required this.state,
    required this.busy,
    required this.onCheck,
    required this.onOpen,
    required this.onRemove,
  });

  final String name;
  final OpenedSecret? state;
  final bool busy;
  final VoidCallback onCheck;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = state;

    final (String line, Color? color, bool openable) = busy
        ? ('Wird geprüft — der Knoten wird gefragt…', null, false)
        : switch (s?.outcome) {
      null => ('Noch nicht geprüft.', null, false),
      OpenOutcome.opened => (
          'Etwas liegt hier für dich.',
          theme.colorScheme.primary,
          true
        ),
      OpenOutcome.noGrantForYou => (
          'Auf diesem Namen liegt nichts an der Adresse, die nur ihr beide '
              'berechnen könnt. Das heisst nicht, dass der Name leer ist.',
          null,
          false
        ),
      OpenOutcome.noEphemeralKey => (
          s?.recipientId == null
              ? 'Dieser Name veröffentlicht keinen Schlüssel — er kann nichts '
                  'empfangen.'
              : 'Empfangsbereit (${s!.recipientId}), hält aber gerade nichts.',
          null,
          false
        ),
      OpenOutcome.noSecretRecord => (
          'Der Anteil ist da, der Chiffretext fehlt — der Eintrag '
              'nextkey.secret steht nicht auf dem Namen.',
          theme.colorScheme.error,
          false
        ),
      OpenOutcome.couldNotDecrypt => (
          'An der richtigen Adresse, lässt sich aber nicht öffnen.',
          theme.colorScheme.error,
          false
        ),
      OpenOutcome.lookupFailed => (
          'Der Knoten hat nicht geantwortet. Das sagt nichts über den Namen.',
          theme.colorScheme.error,
          false
        ),
          };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(name, style: nkMono.copyWith(fontSize: 16))),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Nicht mehr beobachten',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(line, style: theme.textTheme.bodyMedium?.copyWith(color: color)),
            if (s?.detail != null) ...[
              const SizedBox(height: 6),
              Text(s!.detail!, style: theme.textTheme.bodySmall),
            ],
            if (s?.grantRecordKey != null) ...[
              const SizedBox(height: 8),
              SelectableText(s!.grantRecordKey!,
                  style: nkMono.copyWith(fontSize: 11)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton(
                  onPressed: busy ? null : onCheck,
                  child: busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Prüfen'),
                ),
                const SizedBox(width: 12),
                if (openable)
                  FilledButton(onPressed: onOpen, child: const Text('Öffnen')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
