# Personal Hey Friday recognition

The user proposes recording Hey Friday a few times because the current English
Moonshine recognizer rarely recognizes their pronunciation. Implement three local
samples from the existing microphone recorder. This remains the first stage of
Hey Friday → Hex → Laya → tools / optional Gemini.

Choose local acoustic template matching for the first trial. The alternatives are
improving Moonshine's transcript matching (still depends on English recognition)
or training a keyword neural network (requires substantially more data). Match
normalized spectral features with dynamic time warping, allowing changes in speed
and volume. This is a prototype, not speaker authentication.

The UI shows “Hey Friday anlernen” and progress 1/3 to 3/3. Each click records only
the wake phrase, and silence ends the sample. The samples are persisted in Friday's
Application Support directory as spectral templates; temporary recordings are
deleted after enrollment. Enrollment requires voice and bounded duration;
failed samples are repeatable. The user can retrain, replacing the previous set
only after three successful samples. No Hex, Gemini, or cloud service receives
these enrollment recordings.

The existing offline wake worker loads the templates, consumes PCM, and emits the
same wake event with sample offsets and generation. With an enrolled set it uses
template recognition instead of Moonshine. Without enrollment Moonshine remains
the fallback. Pause and resume keep their acknowledgment and stale-event guards.
Recoverable wake errors restart only wake recognition, not Hex or Laya. Fatal audio
errors remain visible. Tests cover matching, unrelated audio, silence, enrollment
validation/persistence, and stale-event/recovery lifecycle. Real pronunciation
still requires the user's live microphone trial.

Also repair the reported compound Safari command by recognizing “open Safari and
search X” as a single Safari search action, which already opens the browser. Do
not execute unsupported additional actions hidden in a search request.
