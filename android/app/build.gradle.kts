import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// META-08 native fixtures use expendable app data. This opt-in affects only
// debug packaging; never install a test entrypoint over the owner's debug app.
val sharedMetadataProof = providers.gradleProperty("rshopSharedMetadataProof").orNull
require(sharedMetadataProof == null || sharedMetadataProof in listOf("true", "false")) {
    "rshopSharedMetadataProof must be true or false"
}

// Load signing properties if available
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) {
        keyPropertiesFile.inputStream().use { load(it) }
    }
}
val releaseStore = providers.environmentVariable("RSHOP_RELEASE_STORE_FILE").orNull
val hasReleaseSigning = keyPropertiesFile.exists() || !releaseStore.isNullOrBlank()

android {
    namespace = "com.retro.rshop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Keep the fork separate from the installed upstream app and its data.
        applicationId = "com.darkaxt.rshop"
        manifestPlaceholders["appLabel"] = "R-Shop"
        testInstrumentationRunner = "com.retro.rshop.OwnedRomInstrumentation"

        // Version values are pulled from pubspec.yaml automatically
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                // JNI exposes only Java values; no C++ objects cross libraries.
                // Avoid sharing a runtime with unrelated plugin NDK versions.
                arguments += "-DANDROID_STL=c++_static"
            }
        }
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStore ?: keyProperties["storeFile"] as String)
                storePassword = providers.environmentVariable("RSHOP_RELEASE_STORE_PASSWORD").orNull
                    ?: keyProperties["storePassword"] as String
                keyAlias = providers.environmentVariable("RSHOP_RELEASE_KEY_ALIAS").orNull
                    ?: keyProperties["keyAlias"] as String
                keyPassword = providers.environmentVariable("RSHOP_RELEASE_KEY_PASSWORD").orNull
                    ?: keyProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = if (sharedMetadataProof == "true") ".sharedproof" else ".debug"
            manifestPlaceholders["appLabel"] =
                if (sharedMetadataProof == "true") "R-Shop Shared Proof" else "R-Shop Drive Dev"
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                null
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

// Publication must never silently use Android's development certificate.
tasks.matching { it.name.startsWith("assembleRelease") || it.name.startsWith("bundleRelease") }
    .configureEach {
        doFirst { check(hasReleaseSigning) { "Configure private R-Shop release signing before packaging." } }
    }

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    // Match the endorsed sign-in plugin; used only for microG's native cache
    // invalidation boundary, not a second sign-in or account provider.
    implementation("com.google.android.gms:play-services-auth:21.6.0")
    implementation("com.hierynomus:smbj:0.13.0")
    // Bounded raw LZMA/LZMA2 decoding for the validated single-ROM N64 7z route.
    implementation("org.tukaani:xz:1.12")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}
