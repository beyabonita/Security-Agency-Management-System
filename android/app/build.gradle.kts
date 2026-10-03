import java.io.FileInputStream
import java.util.Properties
import org.gradle.api.Action
import org.gradle.api.execution.TaskExecutionGraph

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("signing.properties")

if (signingPropertiesFile.exists()) {
    FileInputStream(signingPropertiesFile).use { signingProperties.load(it) }
}

gradle.taskGraph.whenReady(
    object : Action<TaskExecutionGraph> {
        override fun execute(graph: TaskExecutionGraph) {
            if (
                graph.allTasks.any { task -> task.name.contains("release", ignoreCase = true) } &&
                !signingPropertiesFile.exists()
            ) {
                throw GradleException(
                    "Release signing is not configured. Copy android/signing.properties.example " +
                        "to android/signing.properties and create the referenced keystore.",
                )
            }
        }
    },
)

fun signingValue(name: String): String =
    signingProperties.getProperty(name)
        ?: throw GradleException("Missing '$name' in android/signing.properties.")

android {
    namespace = "com.sentinellink.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.sentinellink.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingPropertiesFile.exists()) {
            create("release") {
                keyAlias = signingValue("keyAlias")
                keyPassword = signingValue("keyPassword")
                storeFile = rootProject.file(signingValue("storeFile"))
                storePassword = signingValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // The task-graph guard above blocks release work until a
            // non-versioned keystore configuration is present. The debug
            // fallback only keeps debug development tasks working.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
