plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.movie_tracker"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // Updated this to remove the deprecation warning
    kotlinOptions {
        jvmTarget = "17" 
    }

    defaultConfig {
        applicationId = "com.example.movie_tracker"
        
        minSdk = flutter.minSdkVersion 
        targetSdk = 36
        
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // REVERTED: Use this exact syntax for your version
        multiDexEnabled = true 
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            getByName("release") {
                isMinifyEnabled = false
                isShrinkResources = false
                proguardFiles(getDefaultProguardFile("proguard-android.txt"), "proguard-rules.pro")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Update the version from 2.0.3 to 2.1.4
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
