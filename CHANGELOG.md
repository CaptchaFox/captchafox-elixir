## 1.0.0

- Verify CaptchaFox tokens with siteverify: `CaptchaFox.verify/3` returns `{:ok, %CaptchaFox.Passed{}}` or
  `{:ok, %CaptchaFox.Rejected{}}`, and `{:error, %CaptchaFox.UnavailableError{}}` when CaptchaFox cannot be reached
  in time or answers unexpectedly.
- Elixir 1.18 and later on Erlang/OTP 27 and later, no runtime dependencies.
