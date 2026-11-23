defmodule Integrator.PublicInterfaceTest do
  # Uses the library from outside its namespace, as an integrator does: a function or field that is removed or
  # renamed fails here.
  use ExUnit.Case, async: true

  @secret "ok_11111111000000001111111100000000"
  @sitekey "sk_11111111000000001111111100000000"

  # An empty token is rejected without a request, so no network is needed.
  test "every public function is reachable" do
    client = CaptchaFox.new(@secret)
    with_timeout = CaptchaFox.new(@secret, timeout: 3_000)

    assert describe(CaptchaFox.verify(client, "")) == "rejected: missing-input-response"
    assert describe(CaptchaFox.verify(client, nil)) == "rejected: missing-input-response"

    assert describe(
             CaptchaFox.verify(with_timeout, "", sitekey: @sitekey, remote_ip: "203.0.113.7")
           ) ==
             "rejected: missing-input-response"

    assert describe(CaptchaFox.verify(with_timeout, "", remote_ip: {203, 0, 113, 7})) ==
             "rejected: missing-input-response"

    assert describe({:error, %CaptchaFox.UnavailableError{message: "siteverify did not answer"}}) ==
             "unavailable: siteverify did not answer"
  end

  defp describe(outcome) do
    case outcome do
      {:ok, %CaptchaFox.Passed{challenge_ts: challenge_ts, hostname: hostname}} ->
        "passed: #{challenge_ts} #{hostname}"

      {:ok, %CaptchaFox.Rejected{error_codes: error_codes}} ->
        "rejected: " <> Enum.join(error_codes, ",")

      {:error, %CaptchaFox.UnavailableError{} = error} ->
        "unavailable: " <> Exception.message(error)
    end
  end
end
