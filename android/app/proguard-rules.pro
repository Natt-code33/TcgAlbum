# ML Kit: ComponentDiscovery carga registrars por reflexión.
-dontwarn com.google.mlkit.**
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google.mlkit.vision.common.internal.** { *; }
-keep class com.google.mlkit.vision.common.internal.VisionCommonRegistrar { *; }
-keep class com.google.mlkit.common.** { *; }
-keep class com.google.android.odml.image.** { *; }
