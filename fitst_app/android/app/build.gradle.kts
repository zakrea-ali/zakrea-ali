plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("kotlin-android")
}

android {
    namespace = "com.example.new_project_name"
    
    // تم التعديل إلى 35 لإرضاء الحزم الحديثة
    compileSdk = 35
    
    ndkVersion = "26.1.10909125"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.new_project_name"
        
        // تم رفع الحد الأدنى إلى 24 لحل مشكلة حزمة الصوت
        minSdk = 24
        
        // تم رفع الهدف إلى 35 ليتوافق مع الـ compileSdk
        targetSdk = 35
        
        versionCode = flutter.versionCode()
        versionName = flutter.versionName()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}