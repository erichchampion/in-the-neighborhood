# Troubleshooting API Keys

## Current Status ✅

The configuration is correct:
- ✅ xcconfig files are properly referenced in `project.yml`
- ✅ Build settings show `GOOGLE_BOOKS_API_KEY` is being read
- ✅ `INFOPLIST_KEY_GOOGLE_BOOKS_API_KEY` is set correctly
- ✅ Info.plist has the keys with `$(GOOGLE_BOOKS_API_KEY)` variables

## The Problem

The keys are configured correctly, but they're not appearing in the bundled Info.plist at runtime. This is likely because:

1. **The app needs a clean rebuild** - Xcode caches the Info.plist, and variables are only resolved during the build process
2. **Build settings are resolved, but Info.plist processing happens separately**

## Solution: Clean Build

**In Xcode:**
1. Product → Clean Build Folder (Shift+Cmd+K)
2. Product → Build (Cmd+B)
3. Run the app

**Or from command line:**
```bash
cd /Users/erich/git/github/erichchampion/in-the-neighborhood
xcodebuild clean -project "In the Neighborhood.xcodeproj" -scheme InTheNeighborhood -configuration Debug
xcodebuild build -project "In the Neighborhood.xcodeproj" -scheme InTheNeighborhood -configuration Debug
```

## Verification

After rebuilding, check the debug output. You should see:
```
[APIKeys] Found GOOGLE_BOOKS_API_KEY in Info.plist: ...
[App] Google Books API key available: Yes
```

## How It Works

1. **xcconfig files** define `GOOGLE_BOOKS_API_KEY = ...`
2. **Build settings** read from xcconfig: `GOOGLE_BOOKS_API_KEY = ...`
3. **INFOPLIST_KEY_*** setting injects the value: `INFOPLIST_KEY_GOOGLE_BOOKS_API_KEY = ...`
4. **Xcode processes Info.plist** at build time and replaces `$(GOOGLE_BOOKS_API_KEY)` with the actual value
5. **Runtime** reads from the processed Info.plist in the app bundle

## Alternative: Direct Injection

If `INFOPLIST_KEY_*` still doesn't work after a clean build, we can use a build script to inject the keys directly. But the current setup should work once you do a clean build.
