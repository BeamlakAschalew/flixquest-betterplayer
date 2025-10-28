plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

group = "uz.shs.better_player_plus"
version = "1.0-SNAPSHOT"

val lifecycleVersion = "2.9.4"
val annotationVersion = "1.9.1"
val media3Version = "1.8.0"
val workVersion = "2.10.5"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.13.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.2.20")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

android {
    namespace = "uz.shs.better_player_plus"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    sourceSets["main"].java.srcDirs("src/main/kotlin")
}

dependencies {
    implementation("androidx.media:media:1.7.1")

    implementation("androidx.media3:media3-ui:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-datasource-cronet:$media3Version")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version")

    implementation("androidx.lifecycle:lifecycle-runtime-ktx:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common:$lifecycleVersion")
    implementation("androidx.lifecycle:lifecycle-common-java8:$lifecycleVersion")

    implementation("androidx.annotation:annotation:$annotationVersion")
    implementation("androidx.work:work-runtime:$workVersion")

    //noinspection GradleDependency
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk7:2.2.20")
}
