import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/nk/push.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Notifications are optional, so a build without `google-services.json`
  // starts and works — it simply never offers them. Swallowing this would be
  // wrong in a part the app depends on; this is not one.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(nextkeyBackgroundHandler);
  } catch (_) {}

  runApp(const NextkeyApp());
}
