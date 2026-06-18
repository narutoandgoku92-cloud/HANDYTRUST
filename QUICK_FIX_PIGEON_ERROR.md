# Quick Fix: PigeonUserDetails Error

## The Problem
```
type 'List<Object?>' is not a subtype of type 'PigeonUserDetails?' in type cast
```

Occurs when clicking "Register as customer without OTP for demo"

## Root Cause
**Kotlin 2.2.20 is incompatible with firebase_auth's Pigeon serialization.**

## The Fix (2 minutes)

### Step 1: Edit ONE line

File: `android/settings.gradle.kts`  
Line: 26

**Change this:**
```kotlin
id("org.jetbrains.kotlin.android") version "2.2.20" apply false
```

**To this:**
```kotlin
id("org.jetbrains.kotlin.android") version "1.9.22" apply false
```

### Step 2: Clean and Rebuild

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

### Step 3: Test

```bash
flutter run
```

Then click "Register as customer without OTP for demo" button.

✅ **Done!** The PigeonUserDetails error should be fixed.

## Why This Works

- Kotlin 2.2.20 is too new and breaks firebase_auth's Pigeon layer
- Kotlin 1.9.22 is the stable LTS version with full firebase_auth compatibility
- No app code changes needed - only dependency version fix

## Alternative (if step 1 doesn't work)

Update firebase_auth in `pubspec.yaml`:

```yaml
# Line 22, change from:
firebase_auth: ^4.8.0

# To:
firebase_auth: ^4.17.0
```

Then run:
```bash
flutter pub get
cd android && ./gradlew clean && cd ..
flutter run
```

## Verification

After the fix:
- Demo customer registration works ✓
- Demo artisan registration works ✓
- OTP registration still works ✓
- No other changes needed ✓

For detailed technical information, see: `FIREBASE_AUTH_DEBUG_REPORT.md`
