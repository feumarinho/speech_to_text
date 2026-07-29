# About this fork

A fork of [`csdcorp/speech_to_text`](https://github.com/csdcorp/speech_to_text)
that adds one feature: biasing recognition towards a caller supplied list of
expected terms.

Everything else is upstream, untouched.

## Why

The fork exists for [EchoDICOM Ditado](https://github.com/feumarinho/EchoDICOM-Ditado),
a Flutter app that fills in echocardiogram report parameters by voice — "aorta
35", "PSAP 38", "TAPSE 22". Field testing showed the recognizer handles ordinary
speech well and misses the technical terms consistently. "aorta" comes back as
"horta".

Every correction strategy available — an error dictionary, fuzzy matching, an
LLM pass — works *after* the recognizer has already produced the wrong text.
Vocabulary biasing works *before*: it makes the engine less likely to produce
the wrong word at all. Both iOS and Android expose the capability natively; the
plugin just did not surface it.

## What changed

One commit, two packages, 12 files, +179/-12.

### `speech_to_text_platform_interface` (2.4.0)

| File | Change |
|---|---|
| `lib/speech_to_text_platform_interface.dart` | `SpeechListenOptions.biasingStrings` (`List<String>?`), threaded through the constructor and `copyWith` |
| `lib/method_channel_speech_to_text.dart` | Adds the `biasingStrings` key to the `listen` payload **only when the list is non empty** |

The key is deliberately conditional rather than always present. When the option
is unused the channel payload is exactly what it was before, so a native side
that predates this change is unaffected.

### `speech_to_text` (7.4.0) — iOS and macOS

`darwin/speech_to_text/Sources/speech_to_text/SpeechToTextPlugin.swift`

Backed by `SFSpeechAudioBufferRecognitionRequest.contextualStrings`.

1. The argument is read **outside** the existing `guard let` that extracts
   `partialResults`, `onDevice`, `listenMode` and friends. That guard requires
   every field to be present; adding an optional one to it would turn a missing
   argument into a failed `listen`.
2. Propagated to `listenForSpeech(...)` as a trailing parameter defaulting to
   `nil`, so the existing signature still resolves for existing callers.
3. Applied next to `requiresOnDeviceRecognition`, `taskHint` and
   `addsPunctuation`, only when non empty.

`contextualStrings` is iOS 10+ / macOS 10.15+, below this plugin's own floor of
iOS 13 / macOS 11, so no `#available` guard is needed. The `darwin/` directory
serves both platforms and the property exists on both, so one change covers
them.

### `speech_to_text` (7.4.0) — Android

`android/src/main/kotlin/com/csdcorp/speech_to_text/SpeechToTextPlugin.kt`

Backed by `RecognizerIntent.EXTRA_BIASING_STRINGS`
(`android.speech.extra.BIASING_STRINGS`).

1. Read optionally from the channel arguments alongside `pauseFor`, then
   threaded through `startListening` → `createRecognizer` →
   `setupRecognizerIntent`.
2. Added to the intent guarded on **API 33**, verified below.
3. Added to the recognizer intent memoization.

Point 3 is worth calling out. `setupRecognizerIntent` rebuilds the `Intent`
only when the language, partial results flag, listen mode or pause duration
changed. Without adding the biasing list to that comparison, changing the terms
between two listen sessions would silently reuse the intent built for the
previous list. `previousBiasingStrings` closes that.

The extra is written with `putStringArrayListExtra`, not `putExtra`. In Kotlin
`putExtra(String, ArrayList<String>)` resolves to the `Serializable` overload,
while readers of this extra use `getStringArrayListExtra`.

#### Which API level

`EXTRA_BIASING_STRINGS` and `EXTRA_ENABLE_BIASING_DEVICE_CONTEXT` first appear
in the **API 33** (Android 13, Tiramisu) platform sources, and are absent from
the API 31 and API 32 sources. The guard is
`Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU`. Below that the extra
is not added and recognition is unchanged.

#### `EXTRA_ENABLE_BIASING_DEVICE_CONTEXT`

Present in the same API set, deliberately **not** enabled. It biases towards
on-device context such as contact names — unrelated to caller supplied
vocabulary, varying per device, and carrying privacy implications. It is also
documented to have no effect when `EXTRA_AUDIO_SOURCE` is set. Enabling it by
default without measurement would change recognition behaviour for every
existing user of the plugin.

### `speech_to_text` — Dart passthrough

`lib/speech_to_text.dart` needed **no change**. The option travels inside
`SpeechListenOptions`, and the `copyWith` calls that apply `pauseFor`,
`listenFor` and `localeId` now carry `biasingStrings` through. The deprecated
loose-parameter path has no `biasingStrings` argument to lose. Tests were added
to hold that invariant rather than leaving it to inspection.

## Compatibility

- No public signature changes. The field is optional everywhere it appears.
- Null or empty produces the current channel payload and the current native
  behaviour on every platform.
- Degrades in silence. On Web, Windows, Android below API 33, or against a
  recognition service that ignores the hint, there is no error — only no gain.
- No new dependencies in either package.
- Neither package's version was bumped. Consumers pin the fork through
  `dependency_overrides`, which bypasses version constraints anyway, and
  leaving versions alone keeps the diff clean for a possible upstream PR.

## Base

Branched from `22367e5` (`doc: 7.4.0`) rather than from `main`.

`main` is on `7.5.0-beta.1`. `22367e5` is the exact released 7.4.0 /
2.4.0 pair that the consuming app resolves today, so the only behavioural
difference between the app on pub.dev and the app on this fork is the new
option — no beta changes mixed in.

## Consuming it

Both overrides are required. The option is declared in the platform interface
and consumed by the plugin; one without the other does not work. The `path:`
entries are needed because upstream is a monorepo.

```yaml
dependency_overrides:
  speech_to_text:
    git:
      url: https://github.com/feumarinho/speech_to_text.git
      path: speech_to_text
      ref: biasing-strings
  speech_to_text_platform_interface:
    git:
      url: https://github.com/feumarinho/speech_to_text.git
      path: speech_to_text_platform_interface
      ref: biasing-strings
```

```dart
speech.listen(
  onResult: resultListener,
  listenOptions: SpeechListenOptions(
    biasingStrings: ['aorta', 'átrio esquerdo', 'PSAP', 'TAPSE'],
  ),
);
```

Keep the list to terms actually expected in the utterance. Long lists dilute
the bias and can pull common words towards rare ones.

See `speech_to_text/README.md`, section "Biasing recognition towards expected
terms", for the user-facing documentation.

## Not yet validated

No Flutter or Android SDK toolchain was available where this was written, so
none of the following has been run:

1. `flutter test` in both packages. The change adds unit tests for the option
   reaching the platform, for it surviving `copyWith`, and for the channel key
   being omitted when null or empty — none have been executed.
2. Building the example app for iOS and for Android.
3. The field comparison: one listen session with `biasingStrings` and one
   without, dictating `aorta`, `átrio esquerdo`, `PSAP`, `TAPSE`,
   `septo interventricular`, `fração de ejeção`. This is the measurement that
   decides whether the approach is worth keeping at all.
4. An Android device below API 33, confirming the guard holds and nothing
   throws.

## Upstream

The feature is generic, not specific to the app that motivated it, so it is
worth proposing to `csdcorp/speech_to_text` — but only after item 3 above
produces a real number. Nothing here blocks on that merge.
