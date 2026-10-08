pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")

// Some Flutter installs (distro packages, for example) keep the SDK read-only, and Gradle 9
// refuses read-only project folders. integration_test is the only plugin that lives inside the
// SDK, so it is built from a copy. With a normal Flutter install this does nothing.
findProject(":integration_test")?.let { plugin ->
    if (!plugin.projectDir.canWrite()) {
        val copy = file("../build/sdk-plugins/integration_test")
        copy.deleteRecursively()
        plugin.projectDir.copyRecursively(copy)
        plugin.projectDir = copy
    }
}
