# iOS AVSpeechSynthesizer Background Audio + Pause/Resume Implementation

## Executive Summary

Current implementation in `PlatformBridge.swift` already has pause/resume methods (`pauseSpeaking()`, `resumeSpeaking()`, `continueSpeaking()`). However, **background continuation is not currently supported** due to missing AVAudioSession configuration and Info.plist entitlements. This document provides the cleanest path to enable background audio while preserving existing pause/resume behavior.

## Current State Analysis

### Existing Implementation ✅
- `PlatformBridge.swift` correctly implements:
  - `AVSpeechSynthesizer` with delegate (`AVSpeechSynthesizerDelegate`)
  - Pause/resume controls: `pauseSpeaking(at: .word)`, `continueSpeaking()`
  - State tracking via `emitSpeech()` that reports `speaking` and `paused` flags
  - Proper delegate callbacks: `didPause`, `didContinue`, `didFinish`, `didCancel`

### Missing Pieces ❌
1. **AVAudioSession Configuration**: No audio session setup for background playback
2. **Background Modes Capability**: Not declared in `Info.plist` or entitlements
3. **Remote Control Handling**: No MPRemoteCommandCenter integration (optional, lower priority)

---

## Implementation Recommendation

### Level 1: Basic Background Audio (Recommended - Cleanest)

This approach continues speech in background and preserves pause/resume without exposing lock screen controls.

**Changes Required:**

#### 1. Add Background Modes to Info.plist
```xml
<key>UIBackgroundModes</key>
<array>
    <item>audio</item>
</array>
```
**File:** `packages/ios/OpenCode/Info.plist`

**Why:** Required by iOS to permit background audio playback. This is a capability declaration, not a functional change.

#### 2. Initialize AVAudioSession on PlatformBridge init
Add to `PlatformBridge.swift` constructor (line 20-49):

```swift
private func configureAudioSession() {
  let session = AVAudioSession.sharedInstance()
  do {
    // Category: .playback allows background audio when app is backgrounded
    // Options: none (or .duckOthers if you want speech to lower other audio volume temporarily)
    try session.setCategory(.playback, mode: .default, options: [])
    try session.setActive(true)
  } catch {
    // Graceful degradation: speech will still work in foreground
    print("AVAudioSession setup failed: \(error)")
  }
}
```

**Call location:** Add to `override init()` right after `speech.delegate = self` (line 22)
```swift
speech.delegate = self
configureAudioSession()  // ← Add this line
```

**Why:**
- `.playback` category: Directs iOS that audio is primary to app function
- `mode: .default`: Suitable for all speech scenarios
- `options: []`: No ducking (won't lower music volume). If you want ducking, use `.duckOthers`
- Must call `setActive(true)`: Activates the session so iOS honors the category

#### 3. Deactivate session on app background (Optional but recommended)
Add to background notification handler (line 36-44):

```swift
backgroundObserver = NotificationCenter.default.addObserver(
  forName: UIApplication.didEnterBackgroundNotification,
  object: nil,
  queue: .main
) { [weak self] _ in
  MainActor.assumeIsolated {
    self?.onEvent?("appLifecycle", ["state": "background"])
  }
  // If app goes to background while NOT speaking, deactivate session
  // (saves battery; session will reactivate when needed)
  if !self?.speech.isSpeaking ?? true {
    try? AVAudioSession.sharedInstance().setActive(false)
  }
}
```

**Why:** Non-essential optimization. Deactivates audio session when idle to free system resources, but only when speech is not active.

---

### Level 2: Add Lock Screen Controls (Optional - If Remote Control Needed)

If you want pause/play/skip controls visible on lock screen and in Control Center, add:

#### 2A. Update speechSynthesizer delegate methods
Modify existing delegate extension (lines 362-390) to also update `MPNowPlayingInfoCenter`:

```swift
nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
  Task { @MainActor in
    let infoCenter = MPNowPlayingInfoCenter.default()
    var info = infoCenter.nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = utterance.speechString.prefix(50) // First 50 chars
    info[MPMediaItemPropertyArtist] = "OpenCode"
    info[MPMediaItemPropertyAlbumTitle] = "Speech Synthesis"
    infoCenter.nowPlayingInfo = info
    
    emitSpeech()
  }
}

nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
  Task { @MainActor in
    let infoCenter = MPNowPlayingInfoCenter.default()
    var info = infoCenter.nowPlayingInfo ?? [:]
    info[MPMediaItemPropertyTitle] = "Paused: " + utterance.speechString.prefix(50)
    infoCenter.nowPlayingInfo = info
    
    emitSpeech()
  }
}

nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
  Task { @MainActor in
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil  // Clear lock screen
    if speech.isSpeaking { return }
    speechPartID = nil
    emitSpeech()
  }
}
```

#### 2B. Add remote command handling
Add to PlatformBridge (new method):

```swift
private func setupRemoteControls() {
  let rcc = MPRemoteCommandCenter.shared()
  
  rcc.playCommand.addTarget { [weak self] _ in
    self?.resumeSpeaking()
    return .success
  }
  
  rcc.pauseCommand.addTarget { [weak self] _ in
    self?.pauseSpeaking()
    return .success
  }
}
```

Call from `init()`:
```swift
speech.delegate = self
configureAudioSession()
setupRemoteControls()  // ← Add this
```

**⚠️ Important Caveat:**
According to Stack Overflow findings, `MPRemoteCommandCenter` has **limited effectiveness with AVSpeechSynthesizer**. The lock screen will show controls, but:
- Remote commands fire your handlers correctly
- System doesn't auto-update play/pause indicator state on lock screen
- You must manually sync UI state, which can cause lock screen flicker
- Some users report this approach is "hacky"

**Recommendation:** Only add Level 2 if your UX explicitly requires lock screen controls. Level 1 background audio alone is sufficient for most use cases.

---

## iOS-Native Constraints & Limitations

### ✅ What Works Well
1. **Pause/Resume in background**: `pauseSpeaking(at:)` and `continueSpeaking()` work perfectly in background
2. **State tracking**: `isSpeaking`, `isPaused` properties remain accurate
3. **Delegate callbacks**: All four delegate methods fire correctly in background:
   - `didFinish`, `didCancel`, `didPause`, `didContinue`
4. **Silent mode**: When using `.playback` category, speech respects the Ring/Silent switch (won't interrupt if device is silent)

### ⚠️ Limitations
1. **No Progress Tracking**: AVSpeechSynthesizer doesn't expose playback time/progress
   - No way to display "2:34 / 5:00" on lock screen
   - `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` is called during synthesis, but only tells you *which part* is being spoken, not elapsed time

2. **No Rate Control**: Pause/resume work, but no API to skip forward/backward
   - Users cannot seek to a position in the middle of speech
   - Must stop and restart with new text

3. **Lock Screen Display Quirks**:
   - MPNowPlayingInfoCenter updates don't always reflect actual play/pause state instantly
   - System may not update lock screen button state when you pause via code
   - User AirPods controls work better than lock screen controls

4. **Simulator Limitation**: Background audio does **NOT work in Xcode Simulator**
   - Must test on physical device
   - Foreground pause/resume works fine in simulator

### 🎯 Why AVSpeechSynthesizer vs AVAudioPlayer?
You might wonder: "Why not record speech to disk and use AVAudioPlayer?"
- **Pros**: Full playback control (seek, progress, rate, etc.)
- **Cons**: Adds 2-3 second latency for synthesis, disk I/O complexity, larger code footprint
- **Best for**: Pre-recorded audiobooks or long content where users need scrubbing
- **Current use case**: Real-time TTS for UI feedback—keep AVSpeechSynthesizer ✅

---

## Recommended Implementation Path

### Phase 1: Level 1 (Minimum Viable - Recommended Now)
**Effort:** 10 minutes | **Risk:** Low | **Benefit:** High

1. Add `<key>UIBackgroundModes</key>` + `<array><item>audio</item></array>` to Info.plist
2. Add `configureAudioSession()` method to PlatformBridge
3. Call it from `init()`
4. Test on physical device with app backgrounded

**Result:** Speech continues uninterrupted when user backgrounds app.

### Phase 2: Level 2 (Polish - Only if UX requires lock screen controls)
**Effort:** 30 minutes | **Risk:** Medium | **Benefit:** Medium

1. Implement Level 1 first
2. Add MPNowPlayingInfoCenter updates to delegate methods
3. Add MPRemoteCommandCenter setup
4. Handle edge cases (flicker, state sync issues)

**Result:** Lock screen shows "now playing" info and accepts pause/play commands.

### Phase 3: Full Audiobook Mode (Major refactor - Not recommended unless separate feature)
**Effort:** 2-3 days | **Risk:** High | **Benefit:** Feature-specific

Switch to AVAudioPlayer + pre-synthesis approach for content where users want:
- Real-time progress display
- Seek/scrub capability
- Playback speed control (2x, 1.5x, etc.)
- Chapter navigation

This is **architecturally separate** from Level 1/2 and should not be bundled.

---

## Code Placement Summary

### File: `packages/ios/OpenCode/Info.plist`
Add UIBackgroundModes array with "audio" string.

### File: `packages/ios/OpenCode/OpenCode/Bridge/PlatformBridge.swift`

**Location 1** (Around line 20):
```swift
override init() {
  super.init()
  speech.delegate = self
  configureAudioSession()  // ← ADD THIS
  
  // ... rest of init
}
```

**Location 2** (After line 359, before extension):
```swift
private func configureAudioSession() {
  let session = AVAudioSession.sharedInstance()
  do {
    try session.setCategory(.playback, mode: .default, options: [])
    try session.setActive(true)
  } catch {
    print("AVAudioSession setup failed: \(error)")
  }
}
```

---

## Testing Checklist

### Physical Device (Required)
- [ ] Compile with Level 1 changes
- [ ] Start speaking on device
- [ ] Press Home button (app goes to background)
- [ ] Verify speech continues (speaker output or airpods)
- [ ] Pause via WebView button → speech pauses
- [ ] Resume via WebView button → speech resumes from same point
- [ ] Lock screen → speech continues (no UI visible, which is expected for Level 1)
- [ ] Backgrounding with empty/idle speech → app doesn't hang

### Simulator (Will Fail as Expected)
- [ ] Foreground speech and pause/resume work fine
- [ ] Background audio fails (expected limitation)

### Edge Cases
- [ ] Device ringer switch to Silent → speech still plays (correct for `.playback`)
- [ ] Screen lock → speech continues ✅
- [ ] App backgrounded + another app plays audio → what's expected? (Define based on your UX)

---

## Security & Privacy Notes

- **No permissions required**: AVSpeechSynthesizer is system-provided, no microphone access needed
- **Background Modes capability**: Visible in App Privacy manifest but non-invasive
- **User data**: No additional user data exposure vs. foreground operation

---

## References

### Official Apple Documentation
1. **Configuring Your App for Media Playback**
   - https://developer.apple.com/documentation/avfoundation/configuring-your-app-for-media-playback
   - Covers AVAudioSession categories and background modes

2. **AVAudioSession Category**
   - `.playback` category behavior and options

3. **AVSpeechSynthesizer Delegate Methods**
   - `pauseSpeaking(at:)`, `continueSpeaking()`, and all delegate callbacks

4. **Background Modes Capability**
   - "Audio, AirPlay, and Picture in Picture" capability in Xcode

### Community References
- Stack Overflow: "AVSpeechSynthesizer in background mode" (2013-2024)
- Community findings: `.playback` category is mandatory; `.duckOthers` is optional
- Lock screen integration: Possible but has known quirks with AVSpeechSynthesizer

---

## Decision Matrix

| Requirement | Level 1 | Level 2 | Notes |
|---|---|---|---|
| Background continuation | ✅ | ✅ | Both support it |
| Pause/Resume control | ✅ | ✅ | Already implemented |
| Lock screen display | ❌ | ✅ | Not needed for basic UX |
| Lock screen controls | ❌ | ⚠️ (Limited) | Known quirks with AVSpeechSynthesizer |
| Implementation complexity | Low | Medium | Level 2 adds state sync concerns |
| Risk | Low | Medium | Level 2 may cause lock screen flicker |
| Recommended for this app | ✅ | ❓ | Depends on product UX needs |

---

## Questions to Answer Before Implementation

1. **Do users expect lock screen controls?**
   - If no → Stop at Level 1 ✅
   - If yes → Proceed to Level 2 (but be aware of quirks)

2. **Is speech synthesis always short-duration?**
   - If yes (inline notifications, UI feedback) → Level 1 is perfect
   - If yes, but users want progress display → Consider Level 2 (with caveats)

3. **Will this ever be audiobook-like content?**
   - If no → Level 1
   - If maybe future → Architecture Level 1 for scalability, but don't over-engineer now

4. **Do you need to integrate with music/podcast apps?**
   - If no → No special ducking needed; `.playback` with no options is fine
   - If yes → Use `.duckOthers` to temporarily lower other audio volume during speech
