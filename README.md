# YConstructionMVP

Minimal SwiftUI iPhone field app wired for local Cactus + Gemma 3n E2B inference, without bundling the model into the app itself.

## What is included

- SwiftUI iPhone app target
- Vendored `cactus/apple/cactus-ios.xcframework` so the app builds without checking a full local Cactus workspace into git
- Rear-camera wiring kept in the app, but disabled for the current Gemma 3n transcript-first path
- Local microphone capture with pause-based auto-send
- `Message` model
- `ChatViewModel`
- `AIService` protocol
- `CactusRuntime` Swift wrapper over the real Cactus framework
- `CactusAIService` that prewarms a locally installed Gemma 3n E2B model and answers through `cactus_complete`
- `LocalModelStore` for importing and resolving the model from app-accessible storage
- `MockAIService` kept only for previews and fallback development

## What is intentionally not checked in

- Model folders under `cactus/weights/`
- Local Python environments like `venv/` and `cactus/venv/`
- The rest of a local `cactus/` source checkout outside the vendored iOS framework
- The separate `voice-agents-hack/` sandbox

## Project structure

```text
YConstruction/
├── README.md
├── cactus/
│   └── apple/
│       └── cactus-ios.xcframework
├── YConstructionMVP.xcodeproj/
│   └── project.pbxproj
└── YConstructionMVP/
    ├── Assets.xcassets/
    ├── Models/
    │   └── Message.swift
    ├── Services/
    │   ├── AIService.swift
    │   ├── CactusAIService.swift
    │   ├── CactusRuntime.swift
    │   ├── LocalModelStore.swift
    │   └── MockAIService.swift
    ├── ViewModels/
    │   └── ChatViewModel.swift
    ├── Views/
    │   └── ChatView.swift
    └── YConstructionMVPApp.swift
```

## Current status

- The app launches with `CactusAIService`, not the mock service.
- The app captures local PCM audio from the iPhone mic.
- Voice turns are recorded locally, transcribed, and then sent to Gemma 3n as a short text request.
- Camera context is currently disabled because the active Cactus Gemma 3n path is text-only in this app.
- The app prewarms the local Gemma model before enabling the mic.
- The app auto-sends after you pause speaking.
- Replies are shown on-screen and spoken back out loud.
- The last run surfaces local Cactus runtime metrics such as RAM usage and latency.

## One-time local setup

### 1. The Cactus Apple framework is already vendored

This repo already includes:

```text
/Users/sangeetasinha/Documents/YConstruction/cactus/apple/cactus-ios.xcframework
```

If you need to refresh that framework, build it from a separate upstream Cactus checkout and replace the vendored `cactus-ios.xcframework` in this repo.

### 2. Download the Gemma 3n E2B weights with Cactus installed separately

This app now targets a transcript-first `Gemma 3n E2B` path on iPhone.

```bash
cactus download google/gemma-3n-E2B-it
```

The weights are intentionally excluded from git. Expected folder after download:

```text
/Users/sangeetasinha/Documents/YConstruction/cactus/weights/gemma-3n-e2b-it
```

The folder should contain files like:

- `config.txt`
- `tokenizer.json`
- `token_embeddings.weights`
- many `.weights` files

If you want staged-photo question search over synced report history, also download:

```bash
cactus download Qwen/Qwen3-Embedding-0.6B
```

and import the `qwen3-embedding-0.6b` folder into the app the same way.

### 3. Put the model onto the iPhone

The app no longer bundles the model. The model lives in local app storage on the phone.

Best path:

1. Connect the iPhone to your Mac.
2. Open Finder.
3. Select the iPhone in the sidebar.
4. Open the `Files` tab.
5. Open `YConstructionMVP`.
6. Drag the whole `gemma-3n-e2b-it` folder into that area.

Alternative path:

1. AirDrop or otherwise place the `gemma-3n-e2b-it` folder somewhere visible in the Files app.
2. In the app, tap `Import Model Folder`.
3. Pick the `gemma-3n-e2b-it` folder.

After the folder is present, launch the app and tap `Refresh` if it does not detect the model immediately.

## Run on a physical iPhone 16 Pro

1. Open `/Users/sangeetasinha/Documents/YConstruction/YConstructionMVP.xcodeproj` in Xcode.
2. Select the `YConstructionMVP` target.
3. In `Signing & Capabilities`, choose your Apple team.
4. Keep `Automatically manage signing` enabled.
5. Use a unique bundle identifier such as `com.yourname.yconstructionmvp`.
6. Confirm `cactus-ios.xcframework` is linked.
7. Connect the physical iPhone 16 Pro and enable Developer Mode if prompted.
8. Select the physical phone as the run destination.
9. Delete any old copy of `YConstructionMVP` from the phone.
10. In Xcode, run `Product > Clean Build Folder`.
11. Press `Run`.

App installs are much smaller now because the Gemma weights are no longer copied into the app bundle.

## How the app works now

- The app opens in audio-first mode.
- Tap the large mic button once and talk.
- The app records local audio on-device.
- When you pause long enough, the app automatically stops, transcribes the recording, and sends the transcript.
- `CactusAIService` prewarms the locally installed Gemma 3n E2B model before the mic can be used.
- `CactusRuntime` calls the real `cactus_complete(...)` function locally on the phone with the transcript as the user turn.
- The reply is shown on screen and spoken back out loud.

## Important limitations

- This is a real local voice path, but it is still single-turn capture, not continuous live streaming.
- The auto-stop behavior is implemented in the iPhone app with local audio level detection. It is not a built-in Gemma “stop when user stops talking” feature.
- The model must be present in local app storage before the mic can be used.
- Camera context is intentionally disabled in this Gemma 3n build.
- `cactus auth` and `GEMINI_API_KEY` are not needed for this on-device path.
- If the Gemini API key you pasted is real, revoke it.

## Next steps

1. Run the app on the physical iPhone 16 Pro
2. Approve microphone and speech-recognition permissions
3. Verify one full local voice-to-transcript-to-Gemma 3n round-trip
4. Add a dedicated local STT model if you want to remove the Apple Speech transcription dependency
5. Add construction-specific tools on top of the same `AIService` abstraction
