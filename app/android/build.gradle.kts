allprojects {
    repositories {
        google()
        mavenCentral()
        // flutter_webrtc тянет audioswitch с jitpack
        maven { url = uri("https://jitpack.io") }
    }
}

// Форсим compileSdk 36 у всех модулей (плагины требуют минимум 36).
// Стоит ДО evaluationDependsOn, иначе afterEvaluate падает на "already evaluated".
subprojects {
    val forceCompileSdk = {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                android.javaClass
                    .getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                    .invoke(android, 36)
            } catch (e: Exception) {
            }
        }
    }
    if (state.executed) {
        forceCompileSdk()
    } else {
        try {
            afterEvaluate { forceCompileSdk() }
        } catch (e: Exception) {
            forceCompileSdk()
        }
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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
