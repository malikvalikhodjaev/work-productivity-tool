import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeys = Properties()
val releaseKeyFile = System.getenv("IW_ANDROID_KEY_PROPERTIES")?.let { File(it) } ?: rootProject.file("key.properties")
if (releaseKeyFile.exists()) releaseKeyFile.reader(Charsets.UTF_8).use { releaseKeys.load(it) }
val focusEdition = providers.gradleProperty("target").orNull?.endsWith("focus_main.dart") == true || providers.gradleProperty("iwFocus").orNull == "true" || System.getenv("IW_FOCUS_EDITION") == "1"

android {
    namespace = "uz.iw.indicators_work"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (focusEdition) "uz.iw.focus_norms" else "uz.iw.indicators_work"
        manifestPlaceholders["iwAppLabel"] = if (focusEdition) "Focus & Norms" else "Indicators & Work Dashboard"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeyFile.exists()) create("ownerRelease") {
            storeFile = File(releaseKeys.getProperty("storeFile"))
            storePassword = releaseKeys.getProperty("storePassword")
            keyAlias = releaseKeys.getProperty("keyAlias")
            keyPassword = releaseKeys.getProperty("keyPassword")
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("ownerRelease")
        }
    }
    if (focusEdition) sourceSets.getByName("release").manifest.srcFile("src/focus/AndroidManifest.xml")
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && !releaseKeyFile.exists()) {
        throw GradleException("Release APK requires a private signing key. Set IW_ANDROID_KEY_PROPERTIES or android/key.properties; see native-app/README.md.")
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
