# R8 rules of the RELEASE build (android/app/build.gradle.kts adds this file
# to Flutter's own rules). R8 removes what nothing references and renames
# the rest; everything that is found BY NAME at run time — from the manifest,
# by WorkManager, through JNI, by a library's reflection — has to be listed
# here or it disappears without a build error and fails on the phone.
#
# Most libraries bring their own rules. What follows repeats the ones this
# app depends on, on purpose: a library update must not be able to take a
# rule away unnoticed. Keeping a little too much costs a few kilobytes;
# keeping too little costs a customer's printer, report or licence.

# ---- Readable native stack traces ----------------------------------------
# The Android side's crash log (CrashLog.kt -> errors-native.log) is only
# useful with file names and line numbers in it.
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# ---- Souqi's own Android code --------------------------------------------
# Small, and all of it is reached from outside the Java code:
#   MainActivity, SouqiFileProvider  - named in AndroidManifest.xml
#   DebtReportWorker                 - created by WorkManager from its class
#                                      NAME, which is stored in WorkManager's
#                                      database across app updates: it must
#                                      never be renamed
#   PrinterConnection, ReportChannel, ReportFiles, ReportScheduler,
#   LicenseChannel, CrashLog         - the platform channels "souqi/native",
#                                      "souqi/report" and "souqi/license"
# Kept whole and under their own names, so a crash report says where.
-keep class com.souqi.souqi.** { *; }

# ---- WorkManager (the daily debt report and the daily backup) -------------
# Workers are instantiated by reflection with exactly this constructor.
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class androidx.work.WorkerParameters
# WorkManager starts itself through androidx.startup, which reads the
# initializer's class name from the manifest...
-keep class * implements androidx.startup.Initializer { <init>(); }
-keep class androidx.work.WorkManagerInitializer { *; }
# ...and keeps its queue in a Room database whose generated implementation
# is looked up as "<name>_Impl".
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
# The services and receivers WorkManager declares in its manifest.
-keep class androidx.work.impl.background.systemjob.SystemJobService
-keep class androidx.work.impl.background.systemalarm.** { <init>(...); }
-keep class androidx.work.impl.utils.ForceStopRunnable$BroadcastReceiver
-keep class androidx.work.impl.diagnostics.DiagnosticsReceiver

# ---- File providers (sharing an invoice, a report, the error log) ---------
-keep class androidx.core.content.FileProvider { *; }
-keep class * extends androidx.core.content.FileProvider

# ---- flutter_secure_storage (the card-code key, the licence copy) ---------
# Its ciphers are chosen by names stored on the phone.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# ---- mobile_scanner + the bundled ML Kit barcode model --------------------
# ML Kit finds its components through registrar class names in the manifest,
# and the bundled scanner's native library calls back into these classes
# through JNI.
-keep class dev.steenbakker.mobile_scanner.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { *; }
-keep class com.google.mlkit.common.internal.** { *; }
-keep class com.google.mlkit.vision.barcode.** { *; }
-keep class com.google.mlkit.vision.common.internal.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.photos.vision.barhopper.** { *; }
-keepclasseswithmembernames class * { native <methods>; }

# ---- The other plugins ----------------------------------------------------
# Registered directly by GeneratedPluginRegistrant (no reflection); kept by
# name so a platform-channel failure is readable in a crash report.
-keep class com.tekartik.sqflite.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class io.flutter.plugins.imagepicker.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# ---- Flutter itself -------------------------------------------------------
# Flutter's Gradle plugin adds its own rules for io.flutter.**; repeated for
# the parts the engine calls through JNI.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.util.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core is referenced by the Flutter engine's deferred-components code
# and is not part of this app (no Play Store delivery).
-dontwarn com.google.android.play.core.**
