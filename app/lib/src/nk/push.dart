/// Being told that something arrived, without telling anybody who you are.
///
/// The honest position first: NextKey ran no server at all until the read-only
/// API existed, and a push notification needs one more — something that watches
/// the chain and can reach the phone. So this is opt-in, off until the person
/// turns it on, and the screen that offers it says what it costs.
///
/// What it costs, exactly: the app subscribes to one FCM topic per *watched
/// name*, and the topic is `nk-<first 16 bytes of SHA-256 of the name>`. The
/// notifier therefore learns that some device is interested in a name whose
/// hash it can compute for any name it already knows. It never learns the
/// identity key, never learns which grant is yours, and cannot tell two
/// subscribers apart. The message it sends carries no content: it says a record
/// on that name changed, and the phone does the arithmetic locally to find out
/// whether that means anything for it.
///
/// What it deliberately does not do: subscribe to a topic derived from the
/// grant address. That address is computable only from the shared secret, and
/// handing it to a server would give away precisely what v2 exists to withhold.
library;

import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'crypto.dart';

/// Topic names may hold `[a-zA-Z0-9-_.~%]` only, which the hex below satisfies.
Future<String> topicForName(String name) async {
  final digest = await sha256Bytes(utf8.encode(name.trim().toLowerCase()));
  return 'nk-${hex(digest.sublist(0, 16))}';
}

/// Runs in its own isolate, so it may not touch anything the UI holds. It does
/// nothing but let the system show the notification — the arithmetic happens
/// when the app is opened, with the key, which this isolate has no business
/// unlocking.
@pragma('vm:entry-point')
Future<void> nextkeyBackgroundHandler(RemoteMessage message) async {}

class PushService {
  PushService({FlutterLocalNotificationsPlugin? local})
      : _local = local ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _local;
  static const _channel = AndroidNotificationChannel(
    'nextkey.arrivals',
    'Arrivals',
    description: 'A record changed on a name you are watching.',
    importance: Importance.defaultImportance,
  );

  Future<void> start() async {
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    FirebaseMessaging.onMessage.listen(_show);
  }

  /// Android 13 and later. A refusal is an answer: the app keeps working and
  /// checks on open instead of nagging.
  Future<bool> requestPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized;
  }

  Future<void> watch(String name) async =>
      FirebaseMessaging.instance.subscribeToTopic(await topicForName(name));

  Future<void> unwatch(String name) async =>
      FirebaseMessaging.instance.unsubscribeFromTopic(await topicForName(name));

  Future<void> _show(RemoteMessage message) async {
    await _local.show(
      message.hashCode,
      'Something changed on a name you watch',
      'Open NextKey to check whether it is addressed to you.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          // The payload is never put in the notification: a lock screen is not
          // a place to render something that might be a passphrase.
          styleInformation: const DefaultStyleInformation(false, false),
        ),
      ),
    );
  }
}
