# Befehle

PowerShell, ein Befehl pro Zeile, kein `&&`. Nichts hier committet für dich —
die `git`-Zeilen sind vorbereitet, ausgeführt werden sie von dir.

## Einmalig: ins Repo bringen

Zielrepo ist **`https://github.com/Web3-Degens/nextkey`** — nicht `4bridges/nextkey`.
Der App-Ordner gehört in einen Unterordner `app/`, damit Web, API und App im
selben Repo nebeneinander liegen.

```
cd C:\Users\fundel\Documents
git clone https://github.com/Web3-Degens/nextkey nextkey-degens
```

Den entpackten Ordner `nextkey-app` als `app` hineinkopieren, dann:

```
cd C:\Users\fundel\Documents\nextkey-degens
git add app
git status
git commit -m "app: Android-Empfaengerseite als Flutter-Projekt"
git push
```

`git status` vor dem Commit ist kein Ritual: `key.properties`, `*.jks` und
`google-services.json` stehen in `.gitignore`, und genau dort will man einmal
hinsehen, bevor etwas Unwiderrufliches passiert.

## Bauen

```
cd C:\Users\fundel\Documents\nextkey-degens\app
flutter create --org li.nextkey --project-name nextkey_app --platforms=android .
flutter pub get
flutter analyze
flutter test
```

`flutter create` überschreibt nichts, was schon da ist — aber prüfe danach, dass
diese vier Dateien noch die aus dem Repo sind:

```
android\app\build.gradle.kts
android\settings.gradle.kts
android\app\src\main\AndroidManifest.xml
android\app\src\main\kotlin\li\nextkey\app\MainActivity.kt
```

Auf einem angeschlossenen Gerät:

```
flutter devices
flutter run
```

## Release-Build für Play

```
keytool -genkey -v -keystore $HOME\keys\nextkey-upload.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
copy android\key.properties.example android\key.properties
notepad android\key.properties
flutter build appbundle --release
```

Ergebnis: `build\app\outputs\bundle\release\app-release.aab`.

Ohne Benachrichtigungen bauen (empfohlen für Version 1): in
`android\app\build.gradle.kts` die Zeile
`id("com.google.gms.google-services")` auskommentieren. Die App startet dann
ohne `google-services.json` und bietet Benachrichtigungen schlicht nicht an.

## Referenzvektoren neu erzeugen

Sie sollten sich nicht ändern. Wenn doch, ist entweder die Portierung oder das
Original verschoben worden — und dann ist der Test genau das, was das merkt.

```
node tool\vectors.mjs
```
