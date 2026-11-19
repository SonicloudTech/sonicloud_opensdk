import com.android.build.gradle.LibraryExtension

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
}

// flutter_pcm_sound 等插件自身锁 compileSdk 33，但其 androidx 依赖要求 ≥34，统一抬高。
// evaluationDependsOn 可能已提前触发部分工程求值，afterEvaluate 对已求值工程会抛错，故双分支。
subprojects {
    val raiseCompileSdk: (org.gradle.api.Project) -> Unit = { p ->
        p.extensions.findByType<LibraryExtension>()?.let { ext ->
            if ((ext.compileSdk ?: 0) < 36) ext.compileSdk = 36
        }
    }
    if (project.state.executed) {
        raiseCompileSdk(project)
    } else {
        project.afterEvaluate(raiseCompileSdk)
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
