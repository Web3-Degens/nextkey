import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Notifications only, and off: with this applied and no
    // `google-services.json` beside it, the build fails outright rather than
    // degrading. Version 1 ships without notifications. To turn them on, put
    // `google-services.json` in this folder, uncomment the line below, and add
    // the matching line to android/settings.gradle.kts:
    //   id("com.google.gms.google-services") version "4.4.2" apply false
    // id("com.google.gms.google-services")
}

// The upload key lives outside the repository. `key.properties` is in
// .gitignore and `key.properties.example` says what belongs in it — a keystore
// committed by accident cannot be un-committed, and Play will not accept a
// second one for the same app.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "li.nextkey.app"
    compileSdk = 36
    // No `ndkVersion`: this app has no native code, and declaring one sends
    // the build looking for an NDK download it does not need. If a plugin ever
    // asks for it, the error says so and it goes back in.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "li.nextkey.app"
        // Flutter's own floor, which is above 23 — and 23 is what matters
        // here, because that is where EncryptedSharedPreferences starts. Below
        // it the identity key would sit in plain preferences, which is not a
        // trade this app makes quietly. Never set this below 23.
        minSdk = flutter.minSdkVersion
        // 36 since 31 August 2026: Play refuses a new app, and every update to
        // an existing one, below Android 16. 35 was enough until that date and
        // is not any more.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Deliberately the debug key, so a local `flutter build` works
                // without secrets — and deliberately not silent about it: an
                // upload signed with the debug key is refused by Play, which is
                // the right failure to meet at upload rather than at install.
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// The AGP 9 spelling of what used to be `kotlinOptions` inside `android {}`.
// It sits at the top level now, and its absence from `android {}` is also what
// lets that block resolve to the current extension type instead of the
// deprecated one — one line, three errors.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
