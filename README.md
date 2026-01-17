# In the Neighborhood

An iOS metasearch application that helps conscious consumers find products at local merchants and ethical online retailers while avoiding mega-retailers.

## Project Structure

This project uses XcodeGen to manage the Xcode project structure. The project is organized into several frameworks:

- **InTheNeighborhood**: Main app target with SwiftUI views
- **MetasearchCore**: Core search orchestration, result aggregation, and prioritization
- **SearchSources**: Individual search source implementations (MapKit, Web Search, Specialized APIs)
- **LocationServices**: Core Location wrapper for location services
- **LLMIntegration**: On-device LLM integration for query enhancement

## Building the Project

1. Install XcodeGen:
   ```bash
   brew install xcodegen
   ```

2. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

3. Open the generated project:
   ```bash
   open InTheNeighborhood.xcodeproj
   ```

## Testing

The project follows Test-Driven Development (TDD) principles. Run tests with:

```bash
xcodebuild test -scheme InTheNeighborhood -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Architecture

The app follows a layered architecture:

- **UI Layer**: SwiftUI views (SearchView, ResultsView, etc.)
- **ViewModel Layer**: State management (SearchViewModel)
- **Service Layer**: MetasearchCoordinator, QueryEnhancer
- **Source Layer**: Individual search sources (MapKit, Web, etc.)
- **Infrastructure**: Location, LLM, Networking

## Key Features

- On-device LLM query enhancement (Mistral 3B via MLX Swift)
- Multi-source metasearch aggregation
- Result filtering (deny list for mega-retailers)
- Prioritization (local > regional > online)
- Location-based local business discovery
- Settings for customization

## Requirements

- iOS 18.0+
- Swift 6.0+
- Xcode 16.0+

## Development Status

This is an MVP implementation following TDD principles. Some features are placeholder implementations:

- MLX Swift integration (currently uses basic rule-based parsing)
- Bookshop.org and Marketplace APIs (placeholders)
- Web search APIs (DuckDuckGo, Bing - placeholders)

## License

[To be determined]
