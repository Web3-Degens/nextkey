# flutter_local_notifications keeps its callbacks by reflection.
-keep class com.dexterous.** { *; }

# Play Core is referenced by the Flutter engine's deferred-components support,
# which this app does not use. Without this, R8 fails the release build on
# classes that are never called.
-dontwarn com.google.android.play.core.**

# Tink, under flutter_secure_storage's EncryptedSharedPreferences.
-keep class com.google.crypto.tink.** { *; }

# ML Kit, under mobile_scanner. R8 strips the barcode model loader, and the
# scanner then fails at run time with "An unexpected error occurred" — which is
# what the first release build did, while the debug build was fine because
# nothing was stripped there.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google.android.odml.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.odml.**
