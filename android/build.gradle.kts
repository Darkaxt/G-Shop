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
        extensions.configure<com.android.build.gradle.LibraryExtension> {
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
