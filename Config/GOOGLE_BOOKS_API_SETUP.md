# Google Books API Setup with iOS App Restrictions

## Current Bundle ID

Your app's bundle ID is: **`com.in-the-neighborhood`**

## Setting Up iOS App Restriction

When your Google Books API key has an iOS app restriction, you need to ensure:

1. **Bundle ID matches exactly** in Google Cloud Console
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Navigate to: APIs & Services → Credentials
   - Find your Google Books API key
   - Under "Application restrictions", select "iOS apps"
   - Add bundle ID: `com.in-the-neighborhood`
   - **Important**: The bundle ID must match exactly (case-sensitive, no spaces)

2. **Enable Books API**
   - In Google Cloud Console, go to: APIs & Services → Library
   - Search for "Books API"
   - Click "Enable" if not already enabled

3. **Verify the Setup**
   - The bundle ID in your app's Info.plist should be: `com.in-the-neighborhood`
   - The bundle ID in Google Cloud Console should match exactly
   - The API key should have "Books API" enabled

## Troubleshooting 403 Errors

If you're still getting 403 errors:

1. **Check Bundle ID Match**
   - Run the app and check the debug output
   - Look for: `[GoogleBooksSearchSource] Current bundle ID: com.in-the-neighborhood`
   - Verify this matches what's in Google Cloud Console exactly

2. **Verify API Key Type**
   - In Google Cloud Console, check that the API key type is "iOS app"
   - Not "Web application" or "Android app"

3. **Check API Enablement**
   - Ensure "Books API" is enabled for your project
   - Go to: APIs & Services → Enabled APIs
   - Verify "Books API" is listed

4. **Wait for Propagation**
   - Changes to API key restrictions can take a few minutes to propagate
   - Try again after 5-10 minutes

5. **Test Without Restrictions**
   - Temporarily remove the iOS app restriction
   - If it works without restriction, the bundle ID is likely the issue
   - Re-add the restriction with the correct bundle ID

## Fallback Behavior

The app is configured to automatically retry without the API key if a 403 error occurs. This means:
- If the API key restriction fails, the app will still work
- Google Books API allows public searches without authentication
- You'll just have lower rate limits without a valid API key

## Debug Output

When you run the app, you should see:
```
[GoogleBooksSearchSource] Bundle ID: com.in-the-neighborhood
[GoogleBooksSearchSource] Using API key (length: 39)
```

If you get a 403 error, you'll see:
```
[GoogleBooksSearchSource] Bad request or invalid API key: 403
[GoogleBooksSearchSource] Current bundle ID: com.in-the-neighborhood
[GoogleBooksSearchSource] NOTE: If your API key has iOS app restrictions, ensure the bundle ID in Google Cloud Console matches exactly: com.in-the-neighborhood
[GoogleBooksSearchSource] Retrying without API key...
```
