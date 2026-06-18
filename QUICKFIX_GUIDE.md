# QUICK FIX GUIDE - Anonymous Auth Setup

## The Problem
When users click "Register as customer without OTP for demo", they get:
```
[firebase_auth/admin-restricted-operation]
```

## The Root Cause
Anonymous authentication is **NOT enabled** in Firebase Console.

## The Solution (3 Steps - 2 Minutes)

### Step 1: Open Firebase Console
Go to: https://console.firebase.google.com/

### Step 2: Select Your Project
Click on the "handytrust" project from the list.

### Step 3: Enable Anonymous Authentication

1. In the left sidebar, click: **Build** → **Authentication**
2. Click the **Sign-in method** tab
3. Look for **Anonymous** in the providers list
4. Click on **Anonymous**
5. Toggle the switch to **Enable**
6. Click **Save**

That's it! 🎉

## Verification

After enabling, test:

1. **Demo Customer Registration:**
   - Click "Register as customer without OTP for demo"
   - Should show form (no error)
   - Fill and submit
   - Should navigate to home

2. **Demo Artisan Registration:**
   - Click "Register as artisan without OTP for demo"
   - Should show form (no error)
   - Fill and submit
   - Should navigate to home

3. **OTP Registration:**
   - Enter phone, get OTP, verify
   - Should still work (no regression)

## What You DON'T Need To Do

- ❌ NO code changes
- ❌ NO recompile
- ❌ NO reinstall
- ❌ NO Firestore rule changes
- ❌ NO Android manifest changes

The code is already correct!

## Why This Fixes The Issue

```
Firebase Console Auth Providers:
├── ✓ Phone Auth (already enabled)
├── ✓ Google Sign-In (optional)
├── ✓ Email/Password (optional)
└── ✓ Anonymous (MISSING - ADD THIS)
        ↑ Without this, signInAnonymously() fails
          with "admin-restricted-operation" error
```

Once enabled:
- `FirebaseAuth.signInAnonymously()` succeeds
- Anonymous user gets created with a UID
- Demo registration flow works
- Both customer and artisan registration work
- OTP registration still works

## Configuration Files (Already Correct)

These don't need changes:
- ✓ `google-services.json` - Valid
- ✓ `lib/core/services/auth_service.dart` - Correct
- ✓ `lib/providers/auth_provider.dart` - Correct
- ✓ `lib/screens/auth/phone_login_screen.dart` - Correct
- ✓ `firestore.rules` - Correct

## Still Having Issues?

If it still doesn't work after enabling:

1. Clear app cache: `flutter clean`
2. Rebuild: `flutter pub get` then `flutter build apk --debug`
3. Reinstall the app on device
4. Check Firebase Console settings again to confirm "Anonymous" is enabled

For more details, see: `AUTH_AUDIT_REPORT.md`
