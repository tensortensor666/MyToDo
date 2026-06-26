plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun env(name: String): String = System.getenv(name).orEmpty()

fun hasReleaseSigning(): Boolean {
    return listOf(
        "MYTODO_ANDROID_KEYSTORE_PATH",
        "MYTODO_ANDROID_KEYSTORE_PASSWORD",
        "MYTODO_ANDROID_KEY_ALIAS",
        "MYTODO_ANDROID_KEY_PASSWORD",
    ).all { env(it).isNotBlank() }
}

android {
    namespace = "com.tensortensor666.mytodo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.tensortensor666.mytodo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val keystorePath = env("MYTODO_ANDROID_KEYSTORE_PATH")
            if (keystorePath.isNotBlank()) {
                storeFile = file(keystorePath)
                storePassword = env("MYTODO_ANDROID_KEYSTORE_PASSWORD")
                keyAlias = env("MYTODO_ANDROID_KEY_ALIAS")
                keyPassword = env("MYTODO_ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // R8 minification currently breaks ML Kit barcode scanning on some
            // Android release builds. Keep Java/Kotlin dependencies intact so
            // QR pairing remains reliable.
            isMinifyEnabled = false
            isShrinkResources = false

            // CI release builds must provide a stable keystore through
            // GitHub Secrets so APKs can be upgraded without reinstalling.
            signingConfig = if (hasReleaseSigning()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
