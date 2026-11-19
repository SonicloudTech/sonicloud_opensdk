import java.text.SimpleDateFormat
import java.util.Date

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/arm64-v8a/libopus.so",
                "lib/armeabi-v7a/libopus.so",
                "lib/x86/libopus.so",
                "lib/x86_64/libopus.so"
            )
        }
    }
    namespace = "com.soni.soni_sdk_demo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.soni.soni_sdk_demo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion  // NDK requires minSdk 21 or higher
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "scheme"
    productFlavors {
        create("normal") {
            dimension = "scheme"
            resValue("string", "app_name", "SoniDemo")
            buildConfigField("boolean", "DEVICE_AES256GCM", "false")
        }
        create("bk") {
            dimension = "scheme"
            applicationIdSuffix = ".bk"
            resValue("string", "app_name", "SoniDemoBK")
            buildConfigField("boolean", "DEVICE_AES256GCM", "true")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    android.applicationVariants.configureEach {
        val variant = this
        variant.outputs.forEach { output ->
            if (variant.buildType.name == "release") {
                val buildTime = SimpleDateFormat("yyyyMMdd_HHmm").format(Date())
                (output as com.android.build.gradle.internal.api.ApkVariantOutputImpl).versionCodeOverride =
                    defaultConfig.versionCode!!
                val versionName = variant.versionName
                val versionCode = defaultConfig.versionCode
                val abi = output.getFilter(com.android.build.VariantOutput.ABI)
                val flavor = variant.flavorName
                print("soniSdkDemo_${flavor}_${versionCode}适用${versionName}平台=>>>${abi} time=${buildTime}\n")
                val newApkName =
                    "soniSdkDemo_${flavor}_v${versionName}_${versionCode}_${abi}_${variant.buildType.name}.apk"
                output.outputFileName = newApkName
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 录音笔
//    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.jar", "*.aar"))))
    implementation(
        fileTree(
            mapOf(
                "dir" to "src\\main\\libs",
                "include" to listOf("*.aar", "*.jar"),
                "exclude" to listOf<String>()
            )
        )
    )
    implementation("androidx.appcompat:appcompat:1.0.0")
    implementation("com.polidea.rxandroidble2:rxandroidble:1.17.2")
    implementation("io.reactivex.rxjava2:rxandroid:2.1.1")
    implementation("io.reactivex.rxjava2:rxjava:2.2.8")
    implementation("org.xutils:xutils:3.3.40")

    implementation("com.squareup.retrofit2:retrofit:2.5.0")
    implementation("com.squareup.retrofit2:adapter-rxjava2:2.5.0")
    implementation("com.squareup.retrofit2:converter-gson:2.5.0")
    implementation("com.squareup.retrofit2:converter-scalars:2.5.0")
    implementation("com.squareup.okhttp3:logging-interceptor:3.9.0")

    implementation("io.reactivex.rxjava3:rxjava:3.1.8")

    implementation("org.greenrobot:eventbus:3.3.1")
    implementation("org.greenrobot:greendao:3.2.2")
    implementation("com.koushikdutta.async:androidasync:3.1.0")
}
