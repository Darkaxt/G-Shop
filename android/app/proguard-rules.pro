# Keep smbj and its dependencies intact — R8 minification breaks SMB auth/connection.
-keep class com.hierynomus.** { *; }
-keep class net.engio.** { *; }
-keep class com.hierynomus.smbj.** { *; }
-keep class org.bouncycastle.** { *; }
-keep class org.asn1s.** { *; }

# smbj references javax.el and org.ietf.jgss classes that are not available on Android.
# These are optional features (EL expression filtering, Kerberos/SPNEGO auth) not used by R-Shop.
-dontwarn javax.el.**
-dontwarn org.ietf.jgss.**
-dontwarn org.bouncycastle.**

# Fixed root save-publication entrypoints are loaded from our own installed APK.
-keep class com.retro.rshop.RootSaveProcess { public static void main(java.lang.String[]); }
-keep class com.retro.rshop.RootSavePublicationWorker { public static java.lang.String execute(java.lang.String); }
-keep class com.retro.rshop.RootSaveSourceWorker { public static void serve(); }
-keep class com.retro.rshop.RootSaveWatchWorker { public static void serve(); }
# JNI names are fixed by the independently licensed resource decoder.
-keep class com.github.luben.zstd.** { *; }
-keep class com.retro.rshop.SocketImportNative { *; }
