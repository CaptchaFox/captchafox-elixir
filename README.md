# CaptchaFox for Elixir

Official [CaptchaFox](https://captchafox.com) integration for Elixir. It verifies the answers of the widget with
CaptchaFox.

## Compatibility

| Elixir | Library | Erlang/OTP |
|---|---|---|
| 1.18, 1.19, 1.20 | 1.x | 27, 28, 29 |

Elixir 1.17 and older are not supported: Mix warns when it compiles the library, which then raises on the first
answer of CaptchaFox. Erlang/OTP 26 and older are not supported; nothing prevents the installation there.

## Installation

Add `captchafox` to the dependencies in `mix.exs`:

```elixir
def deps do
  [{:captchafox, "~> 1.0"}]
end
```

Then run `mix deps.get`. The library needs nothing but Elixir and Erlang/OTP; it starts the OTP applications `:inets`,
`:public_key` and `:ssl` that it uses. It checks the certificate of CaptchaFox against the CA certificates of the
operating system; where the operating system provides none, `verify` raises a `RuntimeError`.

## Configuration

### Get your keys

In the [CaptchaFox portal](https://portal.captchafox.com), open your website under **Sites > Site Details** and copy
the **site key** and the **secret key**.

### Set up the library

Create a client once with the secret key of your site and reuse it; it holds no process and can be shared freely.
Keep the secret key in your configuration or environment, not in source code:

```elixir
client = CaptchaFox.new(System.fetch_env!("CAPTCHAFOX_SECRET"))
```

### Options

| Option | Default | Meaning |
|---|---|---|
| `timeout` | 5000 | How long a verification may take in milliseconds, from connecting to CaptchaFox to the end of its answer: `CaptchaFox.new(secret, timeout: 3_000)` |

## Usage

The widget adds the token to the form as the POST parameter `cf-captcha-response`. Verify it on the server before
the form is processed, such as in a Phoenix controller:

```elixir
# A visitor can post the parameter as a map or list; verify takes only a string or nil.
token =
  case params["cf-captcha-response"] do
    token when is_binary(token) -> token
    _ -> nil
  end

case CaptchaFox.verify(client, token, sitekey: site_key, remote_ip: conn.remote_ip) do
  {:ok, %CaptchaFox.Passed{}} ->
    process_form(conn, params)

  {:ok, %CaptchaFox.Rejected{}} ->
    reject_form(conn)

  {:error, %CaptchaFox.UnavailableError{}} ->
    # CaptchaFox gave no usable answer: decide whether the form passes.
    reject_form(conn)
end
```

`verify(client, token)` sends the token alone; the options `sitekey` and `remote_ip` also send the site key the token
was issued for and the visitor's IP address, each only when it is not `nil` or empty. `remote_ip` takes a string or a
tuple such as `conn.remote_ip`.

A verification has one of three outcomes:

- `{:ok, %CaptchaFox.Passed{}}`: CaptchaFox accepted the token. `challenge_ts` and `hostname` hold the time of the
  challenge and the hostname of the site, where CaptchaFox sent them.
- `{:ok, %CaptchaFox.Rejected{}}`: CaptchaFox rejected the token; `error_codes` holds its error codes, such as
  `timeout-or-duplicate`, possibly none. An empty or missing token is rejected with `missing-input-response` without
  asking CaptchaFox.
- `{:error, %CaptchaFox.UnavailableError{}}`: CaptchaFox gave no usable answer; see
  [If CaptchaFox is unreachable](#if-captchafox-is-unreachable).

## Operation

### If CaptchaFox is unreachable

When CaptchaFox cannot be reached, does not complete its answer within the timeout, answers with an HTTP status other
than 200, or with a body that is no valid answer, `verify` returns `{:error, %CaptchaFox.UnavailableError{}}`. Your
code decides whether the form passes then: letting it through keeps your forms available during an outage, rejecting
it keeps them protected. Tokens that CaptchaFox rejects are always `{:ok, %CaptchaFox.Rejected{}}`.

### Log

The library logs nothing, not even a failed TLS handshake with CaptchaFox. The messages of its errors never contain
the secret key, and an inspected client does not show it.

### Visitor IP

The visitor's IP address is sent only when you pass it as `remote_ip`. Behind a reverse proxy or load balancer, pass
the visitor's address that the proxy forwards, not the address of the proxy.

### Privacy

CaptchaFox is operated by Scoria Labs GmbH, Germany. How CaptchaFox processes data and how to get a data processing
agreement is described in the [CaptchaFox Privacy Center](https://captchafox.com/privacy). A suggested paragraph for
your privacy policy is on the [GDPR page](https://captchafox.com/privacy/gdpr).

## License

Apache-2.0. See [LICENSE](LICENSE).
