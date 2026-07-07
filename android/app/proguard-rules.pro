# Proguard rules for cucumber_detect
# Add project specific ProGuard rules here.
# By default, the flags in this file are appended to flags specified
# in C:\Users\sabil\AppData\Local\Android\sdk/tools/proguard/proguard-android.txt
# You can edit the include path and analysis rules here.

# Suppress warnings for missing java.beans classes referenced by snakeyaml (commonly used by YOLO/TFLite wrappers)
-dontwarn java.beans.**
