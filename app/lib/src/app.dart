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

  Future<void> _load() async {
    final me = await store.read();
    if (!mounted) return;
    setState(() {
      _me = me;
      _loading = false;
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
      return OnboardingPage(store: store, onDone: _load);
    }

    final pages = [
      HomePage(identity: me, store: store),
      InboxPage(identity: me, store: store, inbox: inbox),
      SettingsPage(store: store, identity: me, onChanged: _load),
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
