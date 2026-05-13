# ═══════════════════════════════════════════════════
# Flutter 기본 (모든 Flutter 앱 필수)
# ═══════════════════════════════════════════════════
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# ═══════════════════════════════════════════════════
# ⭐ Agora RTC SDK (Phase 2-3)
# ═══════════════════════════════════════════════════
-keep class io.agora.** { *; }
-keep class io.agora.rtc.** { *; }
-keep class io.agora.rtc2.** { *; }
-keep class io.agora.base.** { *; }
-keep class io.agora.spatialaudio.** { *; }
-dontwarn io.agora.**

# Agora native methods (JNI 호출 보존)
-keepclassmembers class io.agora.** {
    native <methods>;
}
-keepclasseswithmembernames class io.agora.** {
    native <methods>;
}

# Agora 콜백 인터페이스
-keep interface io.agora.rtc.** { *; }
-keep interface io.agora.rtc2.** { *; }

# ═══════════════════════════════════════════════════
# Firebase (Crashlytics, Messaging, Analytics 등)
# ═══════════════════════════════════════════════════
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }
-keepclassmembers class * {
    @com.google.firebase.messaging.RemoteMessage <fields>;
}

# ═══════════════════════════════════════════════════
# Supabase / OkHttp / Retrofit 계열
# ═══════════════════════════════════════════════════
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

-keep class io.github.jan.supabase.** { *; }
-dontwarn io.github.jan.supabase.**

# ═══════════════════════════════════════════════════
# RevenueCat
# ═══════════════════════════════════════════════════
-keep class com.revenuecat.purchases.** { *; }
-dontwarn com.revenuecat.purchases.**

# ═══════════════════════════════════════════════════
# Google Play Billing (RevenueCat 의존성)
# ═══════════════════════════════════════════════════
-keep class com.android.vending.billing.** { *; }
-keep class com.android.billingclient.** { *; }

# ═══════════════════════════════════════════════════
# Kotlin / Coroutines
# ═══════════════════════════════════════════════════
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }

# ═══════════════════════════════════════════════════
# Kotlin Serialization (Supabase가 사용)
# ═══════════════════════════════════════════════════
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# ═══════════════════════════════════════════════════
# 일반 - JSON 직렬화/역직렬화
# ═══════════════════════════════════════════════════
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ═══════════════════════════════════════════════════
# ⭐ Kyorang 앱 모델 클래스 (JSON 직렬화 대상 보존)
# ═══════════════════════════════════════════════════
-keep class com.kyorang.** { *; }
-keepclassmembers class com.kyorang.** {
    *;
}

# ═══════════════════════════════════════════════════
# Image picker / file_picker / 기타 plugin
# ═══════════════════════════════════════════════════
-keep class androidx.lifecycle.** { *; }
-dontwarn androidx.lifecycle.**

# ═══════════════════════════════════════════════════
# 디버그 정보 (크래시 리포트에서 줄 번호 보이게)
# ═══════════════════════════════════════════════════
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile

# ═══════════════════════════════════════════════════
# WebView (필요할 수도)
# ═══════════════════════════════════════════════════
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void openFileChooser(...);
}

# ═══════════════════════════════════════════════════
# Parcelable / Serializable
# ═══════════════════════════════════════════════════
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ═══════════════════════════════════════════════════
# ⭐ Release 빌드 로그 제거 (선택 - APK 크기 최적화)
# ═══════════════════════════════════════════════════
# Log.d / Log.v / Log.i 호출을 release 빌드에서 제거
# Log.w / Log.e는 유지 (크래시 디버깅용)
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}