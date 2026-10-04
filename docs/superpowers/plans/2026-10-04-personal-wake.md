# Personal wake and routing repair

1. Reproduce compound Safari rejection and invalid PCM failures in regression tests.
2. Accept opening Safari plus searching as one direct search action; normalize PCM.
3. Add bounded local acoustic templates and rolling subsequence DTW. Keep continuous
   “Hey Friday, command” activation, generation-relative offsets, and silence gates.
4. Add three-sample enrollment to the existing recorder. Route enrollment completion
   away from Hex and command handling. Replace the profile atomically; show retryable
   errors and enrollment progress. Add a local reset option.
5. Recover wake failures without stopping STT/decision models; reject stale events.
6. Preload and retain Hex, verify real local Laya routing, run unit tests, build/sign
   Friday, and push. Clearly distinguish fixture tests from the user's live trial.

Spec review accepted the prototype with rolling matching, bounded noise/warp gates,
and separate wake recovery. Enrollment and actual pronunciation need a live trial.
