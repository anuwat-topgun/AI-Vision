plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "com.example.aivision"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.example.aivision"
        minSdk = 31 // Android 12 tablet baseline (README §2.1)
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }
    // Rust .so files are produced by scripts/build_android_core.sh
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")
    sourceSets["main"].java.srcDirs("src/main/java", "build/generated/uniffi")
    // Golden fixtures for instrumented tests (README §16.2)
    sourceSets["androidTest"].assets.srcDirs("../../../fixtures/media")
    androidResources { noCompress += "mp4" }
    buildFeatures { compose = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions { unitTests.isReturnDefaultValues = true }
}


dependencies {
    val bom = platform("androidx.compose:compose-bom:2025.09.00")
    implementation(bom)
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.compose.ui:ui")
    implementation("net.java.dev.jna:jna:5.17.0@aar") // UniFFI Kotlin runtime
    val media3 = "1.8.0"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.3.0")
    androidTestImplementation("androidx.test:runner:1.7.0")
}

kotlin { compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) } }
