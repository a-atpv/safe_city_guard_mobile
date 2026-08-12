# Gradle-плагин Flutter включает R8 в release сам, даже когда в build.gradle.kts
# минификации не видно. flutter_local_notifications хранит кэш отложенных
# уведомлений через Gson, а Gson без generic-сигнатур падает с
# "TypeToken must be created with a type argument" — на КАЖДОМ show()/cancel().
# То есть без правил ниже сирена SOS в release-сборке молча не показывается
# вовсе (найдено 2026-08-13 по logcat: PlatformException в
# FlutterLocalNotificationsPlugin.loadScheduledNotifications).
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keep class com.dexterous.flutterlocalnotifications.** { *; }
