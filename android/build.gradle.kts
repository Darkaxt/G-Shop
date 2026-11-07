allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
    // Bound plugin Ninja compile/link work too, not just the app JNI target.
    // Gradle's two workers can run two ABI tasks; each uses one shared pool.
    plugins.withId("com.android.library") {
        if (project.name == "file_picker") {
            // Picker 11 assumes AGP 9's built-in compiler; this stable Flutter
            // stack explicitly uses external Kotlin. Match its Java 17 target.
            pluginManager.apply("org.jetbrains.kotlin.android")
            extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension> {
                compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            // Keep plugin native intermediates owned by this checkout instead
            // of writing .cxx output into the shared Pub package sources.
            externalNativeBuild.cmake.buildStagingDirectory =
                rootProject.file(".cxx/${project.name}")
            defaultConfig.externalNativeBuild.cmake.arguments.addAll(listOf(
                "-DCMAKE_JOB_POOLS=rshop_native=1",
                "-DCMAKE_JOB_POOL_COMPILE=rshop_native",
                "-DCMAKE_JOB_POOL_LINK=rshop_native"
            ))
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
