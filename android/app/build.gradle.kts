import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// THE RELEASE KEY.
//
// android/key.properties (git-ignored, see android/.gitignore) says where the
// release keystore is — a file OUTSIDE this repository — and its passwords:
//
//     storeFile=C:/SouqiKeys/souqi-release.jks     (forward slashes)
//     storePassword=...
//     keyPassword=...
//     keyAlias=souqi
//
// Every customer's activation depends on this one keystore: the request code
// of a phone is derived from the key the app is signed with (ANDROID_ID), and
// the app compares its own signing certificate with
// `expectedSigningCertSha256` (lib/core/licensing/license_keys.dart) at every
// start. A build signed with ANY OTHER key shows a different request code and
// refuses to sell. Never replace the keystore; never lose it or its password.
// README.md has the backup rules.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.souqi.souqi"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The package name is part of every phone's request code
        // (`deviceHashOf`): it can never change.
        applicationId = "com.souqi.souqi"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From `version:` in pubspec.yaml ("1.0.0+1" = name 1.0.0, code 1).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // With android/key.properties: the release key. Without it the
            // build still works — `flutter run --release` on the developer's
            // own phone — but it is signed with the DEBUG key: such an APK
            // does not match `expectedSigningCertSha256`, reports itself as
            // modified and does not sell. It must never be handed out, and
            // tool/build_release.ps1 refuses to build one.
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }

            // R8: unused code and resources are removed, the rest is renamed.
            // What is reached by name at run time (WorkManager's worker, the
            // file provider, the plugins' reflection) is kept by
            // proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// THE RELEASE APK IS FOR REAL PHONES: arm and arm64. The plugins bring
// x86_64 libraries too (the barcode scanner's alone is 6 MB), for emulators
// that will never install a release. They are left out of the release
// package here — per variant, so a debug build still runs on an emulator.
// (abiFilters cannot do it: Flutter's own list, which includes x86_64, is
// merged with whatever a build type adds.)
androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.add("lib/x86_64/**")
        variant.packaging.jniLibs.excludes.add("lib/x86/**")
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

dependencies {
    // The daily debt report's scheduler (DebtReportWorker.kt). From Google
    // Maven, fetched through the Aliyun mirrors like everything else; no
    // Flutter plugin.
    implementation("androidx.work:work-runtime:2.11.2")
}
