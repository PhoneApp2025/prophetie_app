import com.android.build.gradle.LibraryExtension
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
    // Apply Google Services plugin without pinning a version; version comes from classpath
    id("com.google.gms.google-services")
}

android {
    namespace = "com.simonnikel.phone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.simonnikel.phone"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    signingConfigs {
        create("release") {
            val keyProps = Properties()
            val keyFile = rootProject.file("android/key.properties")
            if (keyFile.exists()) {
                keyProps.load(keyFile.inputStream())
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
                storeFile = keyProps.getProperty("storeFile")?.let { file(it) }
                storePassword = keyProps.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
        debug {
            // debug defaults
        }
    }
}

flutter {
    source = "../.."
}

// Keep dependencies minimal; Flutter plugins add their own
dependencies {
}

subprojects {
    afterEvaluate {
        if (this.name == "uni_links") {
            plugins.withId("com.android.library") {
                extensions.configure(LibraryExtension::class.java) {
                    namespace = "com.github.avioli.uni_links"
                }
            }
        }
    }
}