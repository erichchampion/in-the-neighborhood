# Cancelling llama.cpp inference when the app goes to background

This guide is for developers integrating **llama.cpp with Metal on iOS**. It explains why inference must stop when the app is backgrounded and how to cancel in-progress inference so the app doesn’t crash.

## Why this is required

On iOS, **Metal cannot run in the background**. If the app is sent to the background while llama.cpp is doing Metal work (e.g. during `llama_decode` or `llama_get_logits_ith`), the system will reject GPU work and llama.cpp can crash with:

- **`IOGPUMetalError: Insufficient Permission (to submit GPU work from background)`**
- **`ggml_metal_synchronize: error: command buffer failed`**
- A fatal in `ggml-metal-context.m` when the backend aborts

So you need to:

1. **Stop starting or continuing** high-level work (e.g. “run a search” or “run agent”) when the app goes to background.
2. **Bail out before any Metal-touching call** if the app is not active, so you never let llama.cpp submit GPU work in the background.

## Two-part approach

### 1. Cancel the high-level operation when the app goes to background

As soon as the app enters the background, cancel whatever `Task` (or equivalent) is driving inference. That way you don’t start new inference after backgrounding, and in-flight work will see `Task.isCancelled` (or your own “cancelled” flag) and stop.

**Example (SwiftUI):** Observe `scenePhase` and cancel the operation that owns the inference task.

```swift
// In your root content view (e.g. SearchView)
@Environment(\.scenePhase) private var scenePhase

var body: some View {
    // ... your content ...
    .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .background {
            viewModel.cancelInFlightSearch()  // or whatever cancels the inference-owning task
        }
    }
}
```

**ViewModel:** Expose a method that cancels the single long-running task that may call into the LLM:

```swift
private var searchTask: Task<Void, Never>?

public func cancelInFlightSearch() {
    searchTask?.cancel()
}
```

That task should run your agent/search flow; when it’s cancelled, `Task.isCancelled` will become true inside any async code that’s part of that task (including the llama service).

### 2. Guard every Metal-touching path with an “app active” check

Cancellation is asynchronous. The app can enter the background *between* two llama calls (e.g. after one `llama_decode` and before the next `llama_get_logits_ith`). So in addition to cancelling the task, you must **check “is the app in the foreground?”** immediately before any llama call that can trigger Metal (e.g. `llama_decode`, `llama_get_logits_ith`, or any wrapper that eventually does Metal sync). If the app is not active, throw (or return an error) instead of calling into llama.

**Example (iOS):** Use `UIApplication.shared.applicationState`. Only allow GPU work when `== .active`.

```swift
#if canImport(UIKit)
import UIKit
#endif

/// On iOS, Metal cannot run in background; returns false when app is not active.
nonisolated private static func isGPUWorkPermitted() -> Bool {
    #if canImport(UIKit)
    return DispatchQueue.main.sync { UIApplication.shared.applicationState == .active }
    #else
    return true
    #endif
}
```

**Where to call it:**

- At the **start** of your inference entry point (e.g. before tokenizing or running the model), so you don’t start a new inference in the background.
- At the **start** of the inference loop (e.g. `runInference`).
- **Before each step** that touches the GPU (e.g. before each `llama_decode` and before each `llama_get_logits_ith`), so that if the app is backgrounded mid-inference, the *next* step bails instead of calling Metal.

If not permitted, throw a clear, recoverable error (e.g. “App in background; Metal not permitted”) so callers can treat it as a transient failure and fall back (e.g. to non-LLM search or a message like “Search paused when app was backgrounded”).

**Example: at start of inference and before each decode/logits call**

```swift
guard Self.isGPUWorkPermitted() else {
    throw LLMServiceError.inferenceFailed("App in background; Metal not permitted", reason: .transientFailure)
}
// ... then llama_decode / llama_get_logits_ith / etc.
```

Combine with `Task.isCancelled` so you also stop when the high-level task was cancelled (e.g. from `cancelInFlightSearch()`):

```swift
if Task.isCancelled {
    throw LLMServiceError.inferenceFailed("Inference cancelled", reason: .transientFailure)
}
guard Self.isGPUWorkPermitted() else {
    throw LLMServiceError.inferenceFailed("App in background; Metal not permitted", reason: .transientFailure)
}
```

## Reference in this repo

| Concern | Location |
|--------|----------|
| Cancel in-flight operation when app goes to background | `Sources/InTheNeighborhood/Views/SearchView.swift`: `scenePhase` + `.onChange(of: scenePhase)` calling `viewModel.cancelInFlightSearch()` |
| ViewModel cancel API | `Sources/InTheNeighborhood/ViewModels/SearchViewModel.swift`: `cancelInFlightSearch()` |
| “App active” check and guards before Metal work | `Sources/LLMIntegration/LlamaCppLLMService.swift`: `isGPUWorkPermitted()`, and guards at start of `generateResponse`, start of `runInference`, and in the prompt/generation loops before `llama_decode` / `llama_get_logits_ith` |

## Summary

1. **App lifecycle:** When `scenePhase` becomes `.background`, cancel the task that owns inference (e.g. `searchTask?.cancel()`).
2. **LLM service:** Before every llama call that can use Metal, check `UIApplication.shared.applicationState == .active` (on iOS) and throw if not. Also respect `Task.isCancelled`.
3. **Errors:** Use a transient-failure error so callers can retry or fall back when the user returns to the foreground.

That way you never submit Metal work in the background and in-progress inference is cancelled cleanly when the app is backgrounded.
