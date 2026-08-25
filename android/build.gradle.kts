allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// أُزيلت إعادة توجيه build.buildDirectory المخصّصة إلى "../../build" —
// كانت تُسبّب خطأ Gradle حقيقي على Windows تحديدًا عندما يكون مجلد المشروع
// وملفات pub cache على قرصين مختلفين (مثل D:\ و C:\)، لأن Gradle يفشل في
// حساب مسار نسبي بين جذرين مختلفين لا علاقة بينهما. العودة لمجلدات build
// الافتراضية لكل وحدة (تحت android/build/ و android/app/build/ كالمعتاد)
// تتجنّب هذا الحساب بالكامل، على حساب فقدان ميزة تنظيمية بسيطة فقط (تجميع
// كل مخرجات البناء خارج android/) — لا قيمة وظيفية حقيقية تستحق كسر البناء
// على Windows من أجلها.
// Flutter expects Android artifacts under the project-level build directory.
val flutterBuildDir = rootProject.layout.projectDirectory.dir("../build")
rootProject.layout.buildDirectory.value(flutterBuildDir)

subprojects {
    project.layout.buildDirectory.value(flutterBuildDir.dir(project.name))
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
