import 'package:flutter/material.dart';

import 'nk/ens_rpc.dart';
import 'nk/identity.dart';
import 'nk/inbox.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/inbox_page.dart';
import 'ui/onboarding_page.dart';
import 'ui/settings_page.dart';

class NextkeyApp extends StatelessWidget {
  const NextkeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NextKey',
      debugShowCheckedModeBanner: false,
      theme: nkTheme(Brightness.light),
      darkTheme: nkTheme(Brightness.dark),
      home: const _Root(),
    );
  }
}

class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  final store = IdentityStore();
  late final reader = EnsReader();
  late final inbox = Inbox(reader: reader);

  Identity? _me;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Re-reads the stored key and rebuilds around it.
  ///
  /// `toId` is for the one case where the tab must move: a key has just been
  /// paired. Whoever did that started on some other tab — Settings, usually,
  /// because that is where the pairing entry is — and `_tab` survives the trip
  /// through onboarding, so without this the app answers a successful scan by
  /// returning to the screen the person was trying to leave. The result of
  /// pairing is an identity, so the identity is what it shows.
  Future<void> _load({bool toId = false}) async {
    final me = await store.read();
    if (!mounted) return;
    setState(() {
      _me = me;
      _loading = false;
      if (toId && me != null) _tab = 0;
    });
  }

  @override
  void dispose() {
    reader.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final me = _me;
    if (me == null) {
      return OnboardingPage(store: store, onDone: () => _load(toId: true));
    }

    final pages = [
      HomePage(identity: me, store: store),
      InboxPage(identity: me, store: store, inbox: inbox),
      SettingsPage(
        store: store,
        identity: me,
        onChanged: _load,
        onPaired: () => _load(toId: true),
      ),
    ];

    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.badge_outlined),
              selectedIcon: Icon(Icons.badge),
              label: 'ID'),
          NavigationDestination(
              icon: Icon(Icons.inbox_outlined),
              selectedIcon: Icon(Icons.inbox),
              label: 'Für mich'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Einstellungen'),
        ],
      ),
    );
  }
}
