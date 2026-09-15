# flutter_local_notifications keeps its callbacks by reflection.
-keep class com.dexterous.** { *; }

# Play Core is referenced by the Flutter engine's deferred-components support,
# which this app does not use. Without this, R8 fails the release build on
# classes that are never called.
-dontwarn com.google.android.play.core.**

# Tink, under flutter_secure_storage's EncryptedSharedPreferences.
-keep class com.google.crypto.tink.** { *; }
