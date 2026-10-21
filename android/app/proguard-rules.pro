# Fixed root save-publication entrypoints are loaded from our own installed APK.
-keep class com.retro.rshop.RootSaveProcess { public static void main(java.lang.String[]); }
-keep class com.retro.rshop.RootSavePublicationWorker { public static java.lang.String execute(java.lang.String); }
-keep class com.retro.rshop.RootSaveSourceWorker { public static void serve(); }
-keep class com.retro.rshop.RootSaveWatchWorker { public static void serve(); }
# JNI names are fixed by the independently licensed resource decoder.
-keep class com.github.luben.zstd.** { *; }
-keep class com.retro.rshop.SocketImportNative { *; }
