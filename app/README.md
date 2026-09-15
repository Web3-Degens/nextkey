# NextKey for Android

The recipient's side of NextKey, on a phone. It holds one key, finds what was
left for it, and opens it locally.

It does **not** hold funds, sign transactions, write to the chain, or send a
secret anywhere. Publishing a key, sending a secret and leaving a read receipt
all need a transaction, and all three stay on `nextkey.li`.

```
lib/src/nk/crypto.dart     the construction, ported from web/src/nk-crypto.mjs
lib/src/nk/ens_rpc.dart    text records, read straight from a Sepolia node
lib/src/nk/api.dart        api.nextkey.li, as a convenience and never a dependency
lib/src/nk/identity.dart   the one key, in the Android Keystore, behind a gate
lib/src/nk/inbox.dart      locate the grant, unwrap the content key, open
lib/src/nk/push.dart       optional notifications, and what they cost
test/crypto_test.dart      the port against vectors from the JavaScript
```

## The port is the risky part, so it is the tested part

`lib/src/nk/crypto.dart` is the third statement of one construction — Node,
browser, Dart. The three must agree byte for byte or a grant written on the
site is unopenable on the phone, and nobody finds out until somebody needs it.

`tool/vectors.mjs` computes the reference values with `node:crypto`;
`test/crypto_test.dart` holds them and checks every step: the public key from a
secret, both sides of the ECDH, the wrapping key, `nextkey.g2.<tag>`,
`nextkey.a2.<tag>`, the identity key from a signature, a WebCrypto ciphertext
opened in Dart, and the NextKey ID including its check symbol.

Regenerating them (they should not change):

```
node tool/vectors.mjs
```

## First build

`flutter create` generates the platform folders; the files in this repository
then replace the four that matter. Run it in the app folder:

```
flutter create --org li.nextkey --project-name nextkey_app --platforms=android .
```

It will not overwrite what already exists. Afterwards, check that these four
are still the ones from this repository — `flutter create` writes its own
versions when they are absent:

```
android/app/build.gradle.kts
android/settings.gradle.kts
android/app/src/main/AndroidManifest.xml
android/app/src/main/kotlin/li/nextkey/app/MainActivity.kt
```

`MainActivity` must extend `FlutterFragmentActivity`. With the default
`FlutterActivity` the app builds, installs, runs — and throws the first time
somebody unlocks, which is the one moment it must not.

Then:

```
flutter pub get
flutter analyze
flutter test
flutter run
```

## Release

The upload key is not in this repository and must not be:

```
keytool -genkey -v -keystore $HOME\keys\nextkey-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
copy android\key.properties.example android\key.properties
```

Fill `android/key.properties` in, back the `.jks` up somewhere that is not this
repository, then:

```
flutter build appbundle --release
```

The bundle lands in `build/app/outputs/bundle/release/app-release.aab`. Play
signs the installed app itself; the key above only signs the upload.

Bump `version:` in `pubspec.yaml` before every upload — the build number after
the `+` is what Play orders releases by, and it may never repeat.

## Notifications

Off until switched on, and the app runs without them: a build with no
`android/app/google-services.json` starts, works, and never offers them.

To turn them on, create a Firebase project, add an Android app with the package
name `li.nextkey.app`, download `google-services.json` into `android/app/`, and
leave the `com.google.gms.google-services` plugin line in
`android/app/build.gradle.kts` uncommented. `server/notifier/README.md` says
what the watcher would have to be — and what it must never do.

## Verified on the device

Both of the things that could not be checked where this was written — the
sandbox had no route to Sepolia and none to `api.nextkey.li` — have now been
checked on a Galaxy A53 (Android 14, Flutter 3.47):

1. **The construction, on real hardware.** A known identity secret produced
   `NK-FD99R-T72VS-1E0PH` in the app, byte-identical to the value the Node
   reference computes. `flutter test` is green as well: 12 tests.

2. **The Universal Resolver ABI.** Watching `anna.nextkey.eth` reports it as
   receivable and shows `NK-X3B7Q-6AG76-YWZG5` — the same ID
   `https://api.nextkey.li/demo/v1/name/anna.nextkey.eth` returns, but read
   straight from the node by `ens_rpc.dart`, with no API involved.

Pairing is closed too: `web/src/nk-qr.mjs` draws the code on the ID page, the
app reads `nextkey://identity/v2?sk=<base64url>` from it, and it also accepts a
claim link, whose key sits after the `#`. Typing a key in by hand still works
and is now the fallback rather than the only way.

## Notes for whoever builds this next

Flutter 3.47 ships Gradle 9.3.1, AGP 9.1.0 and Kotlin 2.4.0, and three things
follow from that:

- `kotlinOptions { jvmTarget }` is gone. Worse, its presence inside `android {}`
  forces that block onto the deprecated extension type, so one mistake reports
  three errors. It lives at the top level now, as
  `kotlin { compilerOptions { jvmTarget = JvmTarget.JVM_17 } }`.
- Let `flutter create` write `android/settings.gradle.kts`. A hand-written one
  pins plugin versions that the shipped Gradle wrapper will not accept.
- `share_plus` resolves to 10 here: `Share.share(text, subject:)`, not
  `SharePlus.instance.share(ShareParams(…))`.

Changes only reach the phone over the cable. The installed app keeps running
without it, which makes it easy to spend twenty minutes testing a build from an
hour ago — watch for the `Installing …app-debug.apk` line.
