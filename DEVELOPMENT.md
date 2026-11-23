# Development

## Requirements

Elixir 1.18 or later on Erlang/OTP 27 or later, and Hex (`mix local.hex`). Without a local installation, the Docker
image `elixir:<elixir>-otp-<otp>`, or `hexpm/elixir` for a specific Erlang/OTP release such as 27.0, runs every command
below. The tests need Linux: one of them relies on Linux dropping a connection attempt on a full accept queue.

## Build

```bash
mix compile --warnings-as-errors
```

compiles the library into `_build/`. `mix docs` writes the documentation that Hex publishes to `doc/`; it needs
`mix deps.get` first.

## Test

| Command | Runs |
|---|---|
| `mix test` | The tests against a local siteverify server, including every case of `test/__fixtures__/siteverify-cases.json`. Needs no network once Hex is installed. CI runs it on Elixir 1.18 with Erlang/OTP 27.0 and 27.3, Elixir 1.19 with Erlang/OTP 28 and Elixir 1.20 with Erlang/OTP 29 for every push to `main` and every pull request. |
| `mix test --only live` | The test against `https://api.captchafox.com/siteverify` with the public test keys. Needs the network. |

## Checks

| Command | Checks |
|---|---|
| `mix format --check-formatted` | The code style of `mix format`. |
| `mix compile --warnings-as-errors` | That the library compiles without warnings. |
