# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

SentraVox is a Flutter **Android** app that acts as an automated call-screening voice agent: it screens incoming calls, transcribes the caller (STT), classifies intent + a risk score (local Spanish rules), replies with a **neural Piper voice** and, optionally, a local LLM, and logs/summarizes the call.

All user-facing strings and most code comments are in **Spanish**; STT/TTS locale is `es-CO`. Keep new UI text in Spanish.

Flutter 3.44.2 / Dart 3.12.2 (`sdk: ^3.12.2`). Dependencies are minimal: `sqflite`, `path`, `cupertino_icons`. No state-management, DI, or codegen packages — dependencies are hand-wired in widget `initState`/`build` (see `lib/ui/agent/agent_page.dart:36`).

## Commands

```powershell
flutter pub get
flutter run                      # Android device/emulator; other platforms have no native impl
flutter analyze                  # lints via flutter_lints 6.0
flutter test
flutter test test/widget_test.dart --plain-name "Counter increments smoke test"   # single test
flutter build apk --debug
```

The `android/` build no longer pulls ONNX Runtime for the classifier (the placeholder model was removed). The local LLM uses `llamadart`/llama.cpp, and the neural TTS uses `sherpa_onnx`/`piper_phonemize`. The Piper voice models ship in `android/app/src/main/assets` via `assets/tts/` and the LLM GGUF via `assets/models/`.

## Architecture

### Layering
`lib/features/<feature>/` follows Clean Architecture — `domain/` (entities, repositories as abstract interfaces, usecases as single-method callable classes) → `data/` (datasources, `repositories_impl/`) → `presentation/` (controllers, widgets). Features: `call_agent`, `call_logs`, `call_screening`.

`lib/ui/` holds the actual screens and is *not* per-feature — it imports from `features/`. `lib/shared/services/` holds the raw `MethodChannel` wrappers (`SttService`, `TtsService`, `NlpService`).

Usecases are invoked via `call()`, so instances are used as functions: `classify(text)`, `getCallLogs()`.

### The agent loop
`AgentController` (`lib/features/call_agent/presentation/controllers/agent_controller.dart`) is the real-call orchestrator; the sequencing itself lives in its base class `ConversationLoopController` (a `ChangeNotifier`, see "One conversation loop, two subclasses"). Per committed transcript it:

1. moves through `AgentState` (`idle → intro → listening → analyzing → responding|blocking → closing`),
2. calls `ClassifyText` → `IntentResult {intent, confidence, riskScore}`,
3. asks `DialogueEngine` for the next line of the screening script,
4. writes the facts the engine extracted (name, company, callback) to `MemoryManager` — session map + persistent DB, keyed by phone number,
5. speaks it via `TtsService`, then returns to `listening` — or hangs up if the reply says the call is done.

Risk `> 0.7` short-circuits to `AgentState.blocking`. On `stop()` it summarizes and persists a `CallLogEntry`.

`AgentState` lives in `domain/fsm/agent_fsm.dart` — **not** in the (empty) `domain/entities/agent_state.dart`.

### Dialogue generation: a screening script, not a reply table
`call_agent/domain/dialogue/` is pure and has no I/O, but `DialogueEngine` is **stateful per call** — that is the whole point. It fills slots (`CallerFacts`: name, company, purpose, callback), walks a `ScreeningStage`, and returns a `DialogueReply {text, endCall, notice, facts, stage}`. Create one per call or `reset()` between calls; `seed()` feeds it what memory already knows about the number.

Collaborators: `IntentLabels` (canonicalizes both classifier vocabularies into `CallerIntent`) → `DialogueRules` (predicates + the thresholds/limits) → `DialogueTemplates` (Spanish strings) plus `FactExtractor` (Spanish regex slot filling).

Three invariants exist because breaking them produced the bug this layer was rewritten to fix — an endless "cuéntame más" loop that read the conversation back to the caller:

- **Every reply ends in a concrete question or ends the call.** No open-ended "tell me more" fallback. Unresolved slots, unclear speech, sensitive topics and turn count all have hard caps in `DialogueRules` (`maxSlotAttempts`, `maxUnclearStreak`, `maxRiskWarnings`, `maxCallerTurns`), and hitting any of them closes the call with `endCall: true`.
- **The agent never recites the transcript.** It reports extracted facts ("le anoto quien llama, Ana Ruiz, de Claro; motivo, …"). The old `NlpService.generateResponse` interpolated its own `U: … | A: …` history into the reply, which is what the caller heard.
- **Nothing repeats verbatim twice in a row** (`_say` wraps a repeat in `DialogueTemplates.insist`), and variation is by counter, never `Random`, so the whole script is unit-testable — see `test/features/call_agent/dialogue_engine_test.dart`.

`NlpService` only classifies now. Adding an intent means: keyword rule in `NlpService`, mapping in `IntentLabels`, base risk in `SimulatedRiskModel`, and a `DialogueTemplates.probe` branch if the follow-up question should differ.

### Platform channels (Dart ↔ Kotlin)
All handlers are installed in `MainActivity.configureFlutterEngine`, which keeps the three service objects in fields — leave them as temporaries and the GC collects the handlers, so the channels go silent.

| Channel | Dart side | Kotlin side |
|---|---|---|
| `sentravox/stt` (method) + `sentravox/stt_stream` (event) | `SttService` | `stt/OfflineSttService` (Android `SpeechRecognizer`) |
| `sentravox/tts` | `TtsService` | `tts/OfflineTtsService` (Android `TextToSpeech` + WAV playback) |
| `sentravox/local_llm` | `LocalLlmService` | `llm/LocalModelAssets` (copy GGUF to internal storage) |
| `sentravox/dialer` | `CallControlBridge` | `MainActivity`: default dialer, the call-screening role (`is_screening_role_held` / `request_screening_role`), and call control via `CallAudioController` — `answer_call`, `end_call`, `call_state`, `set_in_call_audio` |
| `sentravox/call_screening` | `CallScreeningBridge` | `AgentCallScreeningService.flutterChannel` (native→Dart) + `MainActivity`: `drainEvents`, `consumePendingActivation` |

Three contracts here are load-bearing for the conversation loop:

- **STT events are `{text: String, isFinal: bool}`**, never bare strings. Partials arrive first and keep changing; only `isFinal` is committed. Native errors go out via `EventSink.error` so the Dart future *rejects* instead of hanging — an `onError` that emitted nothing was the original bug in this layer. `SttService._parse` still accepts a bare String as final, for compatibility.
- **`startListening(continuous: true)` auto-restarts only across silences** (`NO_MATCH` / `SPEECH_TIMEOUT`, capped at 6 consecutive failures). Android's `SpeechRecognizer` ends its session on every utterance, so continuous listening requires restarts. After a *final result* the native side deliberately does **not** restart — Dart owns that call, because the mic must stay shut while the agent speaks or it transcribes its own TTS.
- **`TtsService.speak` resolves when speech actually finishes**, not when the call is dispatched. Kotlin defers the `MethodChannel.Result` until `UtteranceProgressListener.onDone` (→ `true`) or `onStop`/`onError` (→ `false`). This is what makes turn-taking work; don't collapse it back into fire-and-forget.

### Conversation state (`call_agent/domain/conversation/`)
Pure and immutable, in the same spirit as `DialogueEngine` — no I/O, unit-tested in `test/features/call_agent/conversation_test.dart`:

- `ConversationTurn` — one intervention; `intent`/`risk` are set only on caller turns.
- `ConversationContext` — the turn list plus everything derived from it (`maxRisk`, `dominantIntent`, `riskTrend`, `keyMoments`, `durationAt`). `addTurn` returns a new instance rather than mutating.
- `ConversationSummarizer` — renders a `ConversationSummary` (headline, detail chips, recommendation, `RiskLevel`) from a context plus a `now`. Deterministic: same inputs, same summary.
- `SimulatedRiskModel` — risk heuristic for the simulation path, since the Dart `NlpService` returns only an intent label. Intent base score plus per-phrase escalation for social-engineering keywords, clamped to 0..1.

### One conversation loop, two subclasses
`ConversationLoopController` (a `ChangeNotifier`) owns the voice choreography; consumed via `ListenableBuilder`, no state-management package involved. Subclasses supply only the domain hooks:

- `CallSimulationController` — "Probar IA del agente". `NlpService` + `SimulatedRiskModel`, persists nothing.
- `AgentController` - real calls. `RulesClassifierRepositoryImpl`, `DialogueEngine` + `MemoryManager`, optional local LLM, neural TTS, hangs up on high risk, detects the remote hangup and writes the call to history.

Hooks: `greeting`, `onCallStarting`, `analyzeTurn`, `generateReply`, `onTurnAnalyzed`, `onBlocking`, `onCallFinished`.

`generateReply` returns an `AgentReply {text, endCall, notice}`, not a bare string: the agent has to be able to *finish* a call, not only answer. `onCallStarting` runs with the number already set and before the greeting, so `AgentController` can seed the dialogue engine from memory (and so `greeting` can address a known caller by name).

**Do not reimplement the loop in a subclass.** It is shared precisely because the sequencing is subtle:

final transcript → `stopListening` → analyze → reply → `await tts.speak` → **only then** `startListening` again.

Closing the mic before speaking is not optional — leave it open and the recognizer transcribes the agent's own TTS and the conversation feeds back on itself. Risk above `blockingThreshold` (0.7) ends the call instead of resuming. `_processingTurn` guards re-entrancy from late events, and `dispose()` persists an in-flight call so closing the screen mid-call doesn't lose it from history.

### Why STT errors are classified, not just surfaced
`SttErrorPolicy` decides whether an STT error ends the call. This exists because of a real bug: treating every error as fatal killed the conversation after one utterance. Closing the mic to let the agent speak makes Android emit `ERROR_CLIENT`, which is a *consequence of our own stop*, not a failure.

Two independent defenses, both needed:
1. **Native** — `OfflineSttService.suppressNextError` swallows the error that `stopListening()` itself provokes.
2. **Dart** — `SttErrorPolicy.isFatal` treats codes 5–8 (client/timeout/no-match/busy) as transient; the loop resumes listening and only gives up after `maxConsecutiveSttErrors` (3) in a row.

If you touch either, run `test/shared/stt_error_policy_test.dart`.

### Settings live in SharedPreferences, not sqflite
`AgentCallScreeningService` can run with the app closed, so it cannot reach a MethodChannel or Dart's sqflite databases. The shared state therefore lives in Android SharedPreferences via `SentraVoxPrefs` (Kotlin) ↔ `sentravox/settings` channel ↔ `SettingsDatasource` (Dart). `AppSettings`' key constants must stay identical to `SentraVoxPrefs`' or the two sides silently disagree.

`SettingsController` is exposed app-wide through `SettingsScope` (an `InheritedNotifier`), which sits **above** `MaterialApp` in `main.dart` so routes pushed via the navigator key can still reach it. Writes are optimistic and revert on failure, so the toggle never displays a state that wasn't persisted. `AppSettings.agentActivationEnabled` is the gate to check — `securityEnabled` is a master switch that overrides `autoActivateAgent`. Likewise `autoAnswerEnabled` is `agentActivationEnabled && autoAnswer`: answering a call the agent isn't going to attend would just leave dead air.

### Incoming-call flow

**Prerequisite:** Android only calls `onScreenCall` if the app holds `RoleManager.ROLE_CALL_SCREENING` (API 29+) — or is the default dialer on API 24–28. Nothing in this flow runs without it, so the whole feature looks dead while it's missing. Settings and `DiagnosticsPage` ask for it via `CallControlBridge.requestScreeningRole()`; declaring the service in the manifest is not enough.

**The service's manifest permission must be exactly `android.permission.BIND_SCREENING_SERVICE`.** It said `BIND_CALL_SCREENING_SERVICE` for a while, which is not a real permission — with an unrecognized name the system doesn't treat the service as protected, the app is not a valid `ROLE_CALL_SCREENING` candidate, and the role dialog grants nothing. The symptom is a *permission the user cannot grant*, which looks nothing like a manifest typo. It also does not belong in `<uses-permission>`: it's the permission the system must hold to bind us. Editing it means a full reinstall, not a hot reload.

`requestScreeningRole()` returns a `ScreeningRoleRequest`, not a bool, because "nothing happened" is a real outcome (`roleUnavailable` on devices that don't offer the role, `legacyDialer` below API 29). The UI explains it and offers the default-dialer fallback instead of leaving an inert button.

**Diagnosing it:** every gate has the same symptom — the phone rings and nobody answers — so don't debug it by guessing. `CallControlBridge.diagnostics()` → `ScreeningDiagnostics` reports each one, and `DiagnosticsPage` (linked from the home screen, which also shows a warning banner when `canConverse` is false) lists them **in dependency order** with a button each. `ScreeningDiagnostics.headline` names only the first blocking cause, because fixing a later one changes nothing while an earlier one is missing.

The decisive datum is `lastScreening`: `SentraVoxPrefs.recordLastScreening` keeps the most recent decision and, unlike the event queue, is **not** cleared when the history import drains it. No entry there after a real call means `onScreenCall` never ran — a role problem, not an agent problem.

1. `AgentCallScreeningService.onScreenCall` ignores outgoing calls (API 29+ routes them here too) and reads settings from `SentraVoxPrefs`. Protection off → allow, log as `skipped_disabled`.
2. **Unknown caller = not in Contacts.** A `ContactsContract.PhoneLookup` query decides it; without `READ_CONTACTS` it falls back to `callerDisplayName == null`, which is almost always null because networks rarely send CNAP — that fallback alone made "unknown" meaningless.
3. `RiskEvaluator.evaluate(number, blocklist, isUnknownCaller)` scores the number — that's all it has pre-answer, no transcript exists yet. Blocklist matching is suffix-based so `+57…` from the network matches the 10 digits the user typed.
4. Decision order matters: risk ≥ 0.85 → block silently; unknown + `blockUnknown` → block + notify; **unknown + `autoActivateAgent` and risk < `RISK_AGENT_CEILING` (0.7) → agent**; risk ≥ user threshold → block + notify; **known contact + `agentAllCalls` and risk < ceiling → agent**; otherwise allow. The unknown-agent branch deliberately sits above the user threshold: `RISK_UNKNOWN_CALLER` is 0.45 and a threshold below that would otherwise block every unknown caller and make "let the agent answer unknown numbers" unreachable. The known-contact branch sits *below* the threshold so a risky contact is still blocked.
5. Getting the call to the agent uses three vias, because a `MethodChannel` only exists while UI is alive and a call almost always arrives with the app backgrounded or closed (`AgentActivationLauncher`): the activation is written to `SentraVoxPrefs`, `startActivity` is attempted, and a `CATEGORY_CALL` notification with a `fullScreenIntent` is posted. Dart picks the activation up in `main.dart` at bootstrap and on every `AppLifecycleState.resumed`, and `_deferredActivation` holds it if the navigator or the settings aren't ready yet. `_agentPageOpen` still guards against stacking, and `PendingActivation.isFresh` (90 s) drops activations whose call is long over.
6. **Screening does not answer the call, and answering must not depend on the UI.** `CallScreeningService` only allows or blocks; the phone keeps ringing until someone picks up. Answering is a separate operation — `TelecomManager.acceptRingingCall()`, gated on the `ANSWER_PHONE_CALLS` runtime permission, wrapped in `CallAudioController`.

   `AutoAnswer.schedule()` runs it **from the screening service's own process**, right after `respondToCall(allow)`. Doing it in `AgentController.onCallStarting` was not enough and is the reason the phone kept ringing in practice: that code only runs if Android lets us launch an Activity from the background, which it normally doesn't. Two details are load-bearing: allow the call *before* trying to answer (Telecom needs a moment to put it in RINGING, and `acceptRingingCall()` on a call that isn't ringing yet silently does nothing — hence the 2 s delay plus retries every 800 ms), and stop as soon as the state leaves RINGING, so we don't fight the user who picked up.

   `AgentController` still answers as a fallback when the screen does open — speaker route on → answer → `answerSettleDelay` (900 ms) → greeting, in that order, or the greeting plays before the call exists or out of the earpiece. `answerRingingCall` returns `true` when the call is already active, so the fallback path doesn't report a spurious failure. `onCallFinished` hangs up if the agent answered and the script ended on its own, and restores the audio route. Covered end-to-end with fakes in `test/features/call_agent/agent_controller_test.dart`.
7. **Every** branch calls `record(...)`, queueing the outcome in SharedPreferences. `ImportScreeningEvents` drains that queue on next launch into `call_logs` — this is what makes calls filtered while the app was dead still appear in history. The native drain is read-and-clear, so events import exactly once. `consumePendingActivation` also removes the matching `agent` event from that queue: the agent writes its own entry (with transcript and summary) when it hangs up, so leaving it would show the same call twice. **Consume the activation before draining.**

### Persistence
Two separate sqflite databases, each with its own static-`_db` singleton datasource:
- `sentravox_logs.db` → `call_logs` (`CallLogLocalDatasource`), **schema v2** — v2 added the `outcome` column with an `onUpgrade` `ALTER TABLE`. Bump `_schemaVersion` and add an `onUpgrade` branch for further changes; existing installs upgrade in place.
- `sentravox_memory.db` → `memory`, `(number, key, value)` (`MemoryLocalDatasource`), still v1 with no migration path.

`CallOutcome` holds the outcome vocabulary; its first four values are produced by Kotlin and must stay in sync with the constants in `AgentCallScreeningService`. `CallOutcome.isBlocked` deliberately excludes `flaggedHighRisk` — that means the agent detected high risk but could not hang up, so it isn't a block.

`MemoryLocalDatasource.save` is a plain `insert`, so repeated facts accumulate duplicate rows rather than upserting.

## Known incomplete state

This is a work-in-progress prototype. `flutter analyze` is clean (0 issues), `flutter build apk --debug` succeeds (≈1.04 GB with the bundled LLM and two Piper voices), and the suite is green (147 tests). The app was exercised on a Pixel 10 API 37 emulator: simulated incoming call answered with neural TTS, call saved to history, automatic stop when the caller hung up, male/female Piper voices, model copy/load, text-mode fallback and name recognition. The following are real and worth knowing before assuming a feature works end-to-end.

The wiring is complete end to end, but two things gate the real-call path from being trustworthy, and both are about model quality rather than plumbing:

- **The ONNX classifier was removed.** It was a 0-byte placeholder with a 5-word vocab. `RulesClassifierRepositoryImpl` uses `NlpService` + `SimulatedRiskModel`; `HybridClassifierRepositoryImpl` remains for tests/optional models but the app does not use a native classifier. This also removed the old ONNX Runtime and its native/16 KB conflicts.
- **One classifier vocabulary.** `NlpService` (Dart keyword matcher, Spanish labels) feeds `IntentLabels` directly. There is no second English label set to keep in sync anymore. Adding an intent still means: keyword rule in `NlpService`, mapping in `IntentLabels`, base risk in `SimulatedRiskModel`, and a `DialogueTemplates.probe` branch if needed.
- **The user-facing voice is neural.** `NeuralTtsService` runs two Piper VITS models (female `es-MX`, male `es-ES`) through `piper_phonemize` + `sherpa_onnx`, writes a WAV and plays it through `OfflineTtsService.speakWav` using the same in-call route. `HybridTtsService` falls back to the system TTS if the model is not ready. The five profiles live in `lib/shared/voice/voice_profiles.dart` and must match `SentraVoxPrefs.voiceProfile`/`speechRateForProfile`/`pitchForProfile`. The Piper models are Apache-2.0; `piper_phonemize` is GPL-3.0 because of espeak-ng.
- **`AgentPersona` is the single source of prompt/identity.** Name, company, role, personality, owner and formality now reach the dialogue templates and the local LLM prompt. If you add a profile field, wire it here and in `AppSettings`/`SentraVoxPrefs` together.
- **Voice selection is profile-based and neural.** Android exposes no gender API for the system fallback; `OfflineTtsService` still uses voice-name heuristics. The primary path is `NeuralTtsService` with the five profiles. If a Piper model is missing or the first load exceeds 3 s, the turn falls back to the system TTS. The settings UI only exposes the five profiles, not raw voice IDs.
- **Audio injection has two paths, neither guaranteed on PSTN.** `acoustic` (speaker + `USAGE_VOICE_COMMUNICATION`) is the compatible default; `direct` (WAV → `AudioTrack`) is experimental and falls back to acoustic. `auto` tries direct first. The neural TTS WAV goes through the same native playback path, so both modes apply. Android still has no unprivileged uplink API; a production-grade guarantee requires a VoIP/SIP relay, documented in `docs/UPLINK_INJECTION.md`. `Configuración → Ver ruta de audio` reports the real `AudioManager` state.
- **The advanced AI is local.** `LocalLlmService` runs Qwen3.5 0.8B Q4_K_M (Apache-2.0, ≈508 MB) with `llamadart`/llama.cpp on CPU. The GGUF is bundled in `assets/models/`, copied to app storage by `LocalModelAssets` (streaming, not `rootBundle`) and loaded on demand. `LocalLlmResponder` only rewrites non-closing, non-sensitive replies with a compact prompt; if it takes more than 4 s or fails, the local script is spoken. The model is reused across calls through `LocalLlmService.shared` and released when the switch is turned off or the app is disposed. The old `LlmService` OpenAI-compatible client remains as legacy code for `sanitize` and prompt tests, but the UI no longer exposes it.
- **Name presentations are stripped before keyword classification.** `me llamó Edward Mora` used to be classified as billing because `Mora` is a billing keyword. `NlpService._stripSelfIntroduction` removes `me llamo/me llamó/mi nombre es/le habla/le saluda/soy X` before matching, and `FactExtractor` accepts `me llamó`. Keep the name stop words in sync with the extractor if you add forms.
- **STT is resilient and has a simulation text fallback.** `OfflineSttService` prefers the offline `es-CO` pack; on error 12/13/14 it retries once online. `SttErrorPolicy` treats network/server errors (2/3/4) as transient. The simulation sets `allowTextFallback` and exposes `submitText`/the text field, so a missing mic or language pack switches to text mode instead of ending the call. Real calls still fail with a clear notice. `Configuración → Voz sin conexión` opens Android's voice input settings to download the Spanish offline pack.
- **Remote hangup is detected and persisted.** `AgentController.checkCallStateOnce` polls `call_state` every 2 s. Once the call was seen ACTIVE, an IDLE state stops the controller; if ACTIVE was never seen (some phones lag after answering), it waits for three consecutive IDLE checks so a freshly answered call is not cut off. Stopping runs `onCallFinished` and saves the call log with the full two-sided transcript. The monitor is canceled in `onCallFinished` and `dispose`.
- **Home stats refresh on route pop.** `HomePage` is `RouteAware` and subscribes to the global `appRouteObserver` (wired in `MaterialApp.navigatorObservers`). `didPopNext()` reloads the call-log stats, so returning from a finished call updates “Últimas llamadas filtradas” without opening the history. Previously the counters were only loaded in `initState` and after `_openLogs()`, which made a saved call look like “Sin llamadas analizadas hoy”.
- **Name answers without a verb are handled.** `FactExtractor.nameCandidate` accepts 1–5 name-like words after «con», «habla con», «me llamo», «soy», etc., and rejects fillers/verbs. The `DialogueEngine` applies it while the stage is `identifying`. The `con` pattern and `_maxNameWords=5` are what make «con Carlos Andrés Ramírez Gómez» work.
- **A larger model was evaluated and rejected for bundling.** Qwen3.5 2B Q4 (1.28 GB) was ~2.2× slower and did not improve the short rephrase task. `docs/LOCAL_LLM.md` records the comparison, the emulator timings and the steps to swap the GGUF.

Platform limits worth knowing before promising behaviour:

- **Answering and hanging up ride on `ANSWER_PHONE_CALLS`.** `acceptRingingCall()` (API 26+) and `endCall()` (API 28+) both need that runtime permission, which any app can request — being the default dialer is *not* required, contrary to what this file used to say. Both return `false` instead of throwing if the system denies them: `AgentController` surfaces a notice ("contesta tú y el agente sigue la conversación") and `onBlocking` logs `flaggedHighRisk` instead of `blockedByAgent`. Pre-answer blocking via `CallScreeningService` needs neither.
- **Whether the caller actually *hears* the agent is hardware-dependent.** The call now gets answered, but Android offers no API for injecting audio into a call's uplink — that needs system privileges. Two unprivileged paths exist and are selectable in Settings: `acoustic` (call on speaker, TTS with `USAGE_VOICE_COMMUNICATION`, handset mic picks the agent up) and `direct` (synthesized WAV fed to an `AudioTrack` with `USAGE_VOICE_COMMUNICATION`, which some vendor HALs mix into the call). `auto` tries direct and falls back to acoustic. The device's echo cancellation is designed to suppress exactly the speaker→mic path, so how much survives varies by handset. Mic capture during a call is also device-dependent. **Validate on a real phone before promising it works**; the simulation is still the only guaranteed-audible path. The only 100 % route is a VoIP/SIP relay (`docs/UPLINK_INJECTION.md`), which needs a server and is not implemented here.
- **Screening with the app closed reaches Dart late, not never.** There is still no headless Flutter engine, so `activate_agent` over the channel only lands when UI is alive; the activation is persisted natively and picked up at the next bootstrap/resume instead (see step 5 above). Blocking and logging remain fully native. A true background agent would need a cached `FlutterEngine` with its own Dart entrypoint.
- **Full-screen intent is best-effort.** It needs `POST_NOTIFICATIONS` (Android 13+) and, on Android 14+, `USE_FULL_SCREEN_INTENT` is only auto-granted to calling apps; otherwise it degrades to a heads-up notification the user taps. Background `startActivity` is blocked without an exemption on Android 10+ — that's why all three vias exist.
- **`RiskEvaluator` prefix rules are placeholders**, though no longer wrong for Colombia: the old `60…` rule scored every locally-dialed Colombian landline at 0.7 and blocked it above the default threshold. Real signal should come from number reputation and call history.
- **`InCallActivity` / `SentraVoxInCallService` don't exist**; their manifest entries are commented out with a TODO rather than pointing at missing classes.
- **14 empty stub `.dart` files** exist (all of `call_agent/{data/datasources,data/repositories_impl}` for STT/TTS, `domain/repositories/{stt,tts}_repository.dart`, `domain/usecases/{process_transcript,respond_to_intent}.dart`, `shared/services/*/…_adapter.dart`, `classifier_service.dart`, `entities/agent_state.dart`). They're placeholders, not deleted code.
- **`test/widget_test.dart` is a sanity check**, not the counter template anymore. `flutter test` runs the whole suite (147 tests) and is green. The real conversation/settings tests live in `test/features`, `test/shared` and `test/ui`.
- **The settings widget test mocks the platform**; it verifies that the page builds and the prompt preview renders, not real TTS or telephony. Real-device validation is still required.
- **The local LLM and neural TTS are exercised manually on the emulator**, not in unit tests. `LocalLlmService` and `NeuralTtsService` are thin wrappers over native runtimes; tests cover prompts, sanitization, name extraction, the `FakeLlm` controller path and the call-state monitor. The actual GGUF/Piper inference, model copy and memory use need a device/emulator. A fresh install copies ≈508 MB (LLM) + 36 MB (voices) on first use; the debug APK is ≈1.04 GB.

Nothing here has been exercised on a physical device — recognizer restart timing, TTS `onDone`, and the screening service all need a real handset to validate.

**`applicationId` changed** from `com.example.sentravox` to `com.sentravox.sentravox`. Devices with an older build installed need `adb uninstall com.example.sentravox` first.
