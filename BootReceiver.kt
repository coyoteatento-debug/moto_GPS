plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

// ══════════════════════════════════════════════════════════
// LEER KEY.PROPERTIES — generado por GitHub Actions en CI
// Si no existe localmente, usa debug signing como fallback
// ══════════════════════════════════════════════════════════
def keyPropertiesFile = rootProject.file("key.properties")
def keyProperties = new Properties()

if (keyPropertiesFile.exists()) {
    keyPropertiesFile.withInputStream { stream -> keyProperties.load(stream) }
    println("✅ key.properties encontrado — build firmado con keystore real")
} else {
    println("⚠️  key.properties no encontrado — usando debug signing")
}

android {
    namespace = "com.tuempresa.motogps"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.tuempresa.motogps"
        minSdk = 21
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    // ── CONFIGURACIONES DE FIRMA ────────────────────────
    signingConfigs {
        debug {
            storeFile file("${System.getProperty('user.home')}/.android/debug.keystore")
            storePassword "android"
            keyAlias "androiddebugkey"
            keyPassword "android"
        }
        release {
            if (keyPropertiesFile.exists()) {
                storeFile     file(keyProperties['storeFile'])
                storePassword keyProperties['storePassword']
                keyAlias      keyProperties['keyAlias']
                keyPassword   keyProperties['keyPassword']
            } else {
                // Fallback local — NO usar para publicar en Play Store
                storeFile file("${System.getProperty('user.home')}/.android/debug.keystore")
                storePassword "android"
                keyAlias "androiddebugkey"
                keyPassword "android"
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix   = "-debug"
            debuggable          = true
            minifyEnabled       = false
            shrinkResources     = false
            signingConfig       = signingConfigs.debug
        }
        release {
            signingConfig  = signingConfigs.release
            minifyEnabled  = true
            shrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("androidx.work:work-runtime:2.9.0")
    implementation("androidx.core:core-ktx:1.13.1")
}
