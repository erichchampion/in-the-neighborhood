# API Keys Configuration

This directory contains xcconfig files for managing API keys at build time.

## Setup

1. Copy the example files to create your local configuration:
   ```bash
   cp Config/Debug.xcconfig.example Config/Debug.xcconfig
   cp Config/Release.xcconfig.example Config/Release.xcconfig
   ```

2. Edit `Config/Debug.xcconfig` and `Config/Release.xcconfig` and add your API keys:
   ```
   BING_API_KEY = your_actual_bing_api_key_here
   BESTBUY_API_KEY = your_actual_bestbuy_api_key_here
   GOOGLE_BOOKS_API_KEY = your_actual_google_books_api_key_here
   DPLA_API_KEY = your_actual_dpla_api_key_here
   ```

   Notes:
   - **Google Books** works without an API key for public searches; leave blank to use unauthenticated.
   - **DPLA** requires a key. Without one, `DPLASearchSource` short-circuits and the Library tab will only show Open Library and Internet Archive results.
   - **Bing** is optional; without a key the Bing source short-circuits and DuckDuckGo carries the web tab.
   - **BestBuy** is optional; without a key the BestBuy source short-circuits.

3. The `.xcconfig` files are gitignored, so your keys won't be committed to the repository.

## Alternative: Environment Variables

You can also set API keys as environment variables instead of using xcconfig files:

```bash
export BING_API_KEY=your_key_here
export BESTBUY_API_KEY=your_key_here
```

This is useful for CI/CD pipelines where you can set secrets as environment variables.

## How It Works

- The xcconfig files define build settings `BING_API_KEY` and `BESTBUY_API_KEY`
- These are automatically added to Info.plist via `INFOPLIST_KEY_*` settings
- The `APIKeys` enum in the app reads these values from Info.plist at runtime
- If keys are not found in Info.plist, it falls back to environment variables

## Getting API Keys

- **Bing API Key**: Get from [Azure Portal](https://portal.azure.com/) → Cognitive Services → Bing Search API
- **Best Buy API Key**: Get from [developer.bestbuy.com](https://developer.bestbuy.com/login) (free registration)
- **Google Books API**: No API key required - the API works without authentication for public searches
- **DPLA API Key**: Get from [pro.dp.la/developers](https://pro.dp.la/developers/policies#get-a-key) (free; required for any DPLA Library results)
