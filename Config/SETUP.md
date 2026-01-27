# API Keys Setup Instructions

## Current Status

The xcconfig files are properly configured in `project.yml`. However, **you must regenerate the Xcode project** for the changes to take effect.

## Steps to Fix

1. **Regenerate the Xcode project:**
   ```bash
   xcodegen generate
   ```

2. **Clean and rebuild in Xcode:**
   - Product → Clean Build Folder (Shift+Cmd+K)
   - Product → Build (Cmd+B)

3. **Verify the API keys are being read:**
   - Check the debug output when the app starts
   - You should see: `[APIKeys] Found GOOGLE_BOOKS_API_KEY in Info.plist: AIzaSyCDr3...`

## How It Works

1. **xcconfig files** (`Config/Debug.xcconfig` and `Config/Release.xcconfig`) define build settings:
   ```
   BING_API_KEY = your_key_here
   GOOGLE_BOOKS_API_KEY = your_key_here
   ```

2. **project.yml** references these files:
   ```yaml
   configFiles:
     Debug: Config/Debug.xcconfig
     Release: Config/Release.xcconfig
   ```

3. **Build settings** in `project.yml` inject values into Info.plist:
   ```yaml
   INFOPLIST_KEY_BING_API_KEY: $(BING_API_KEY)
   INFOPLIST_KEY_GOOGLE_BOOKS_API_KEY: $(GOOGLE_BOOKS_API_KEY)
   ```

4. **APIKeys.swift** reads from Info.plist at runtime

## Troubleshooting

If keys still aren't found after regenerating:

1. **Check that xcconfig files exist:**
   ```bash
   ls -la Config/*.xcconfig
   ```

2. **Verify keys are in xcconfig files:**
   ```bash
   cat Config/Debug.xcconfig
   ```

3. **Check Xcode build settings:**
   - Open the project in Xcode
   - Select the target → Build Settings
   - Search for "BING_API_KEY" or "GOOGLE_BOOKS_API_KEY"
   - They should show the values from your xcconfig files

4. **Check Info.plist:**
   - The keys should appear in the generated Info.plist
   - Look for `BING_API_KEY` and `GOOGLE_BOOKS_API_KEY` entries

## Alternative: Environment Variables

If xcconfig files don't work, you can set environment variables:

```bash
export BING_API_KEY=your_key
export GOOGLE_BOOKS_API_KEY=your_key
xcodegen generate
```

Then build from Xcode or command line.
