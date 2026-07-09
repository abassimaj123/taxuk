# Flutter + Firebase
-keep class io.flutter.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn io.flutter.**

# AdMob
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Google Play Billing (IAP)
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# ── flutter_local_notifications ──────────────────────────────────────────────
# Without these, R8 strips generic type info from the Gson models used to
# persist scheduled notifications, causing "RuntimeException: Missing type
# parameter" in ScheduledNotificationBootReceiver on device reboot.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken
-keepattributes Signature
-keepattributes InnerClasses
