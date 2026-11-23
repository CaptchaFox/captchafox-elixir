defmodule CaptchaFox.SiteverifyCasesTest do
  # Runs every case of the siteverify specification against a local siteverify.
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias CaptchaFox.{LocalSiteverify, Passed, Rejected, UnavailableError}

  @timeout 5_000
  # Short, so that the cases of a siteverify that stops answering end quickly.
  @silence_timeout 1_000
  # Fails a case whose timeout does not take effect instead of letting it hang.
  @moduletag timeout: 10_000

  @specification Path.join([__DIR__, "__fixtures__", "siteverify-cases.json"])
  @external_resource @specification
  @cases @specification |> File.read!() |> JSON.decode!()

  test "the endpoint is the one of the specification" do
    assert CaptchaFox.new("ok_secret").endpoint == @cases["endpoint"]
  end

  for test_case <- @cases["cases"] do
    @test_case test_case
    test test_case["name"] do
      run(@test_case)
    end
  end

  defp run(%{"input" => input, "answer" => answer} = test_case) do
    secret = input["secret"]

    {server, endpoint, timeout} =
      case answer do
        nil ->
          server = LocalSiteverify.answering(500, "")
          {server, LocalSiteverify.endpoint(server), @timeout}

        %{"error" => "timeout"} ->
          server = LocalSiteverify.silent()
          {server, LocalSiteverify.endpoint(server), @silence_timeout}

        %{"error" => "stall", "status" => status, "body" => body} ->
          server = LocalSiteverify.stalling(status, body)
          {server, LocalSiteverify.endpoint(server), @silence_timeout}

        %{"error" => "connection"} ->
          {nil, LocalSiteverify.refusing_endpoint(), @timeout}

        %{"status" => status, "body" => body} ->
          server = LocalSiteverify.answering(status, body)
          {server, LocalSiteverify.endpoint(server), @timeout}
      end

    try do
      client = %{CaptchaFox.new(secret, timeout: timeout) | endpoint: endpoint}
      opts = Enum.flat_map([sitekey: "sitekey", remote_ip: "remoteIp"], &option(input, &1))

      log =
        capture_log(fn ->
          expect_outcome(
            test_case["expect"],
            secret,
            CaptchaFox.verify(client, input["response"], opts)
          )
        end)

      assert log == "", "the library logged #{inspect(log)}"
      expect_request(test_case["request"], server)
    after
      if server do
        LocalSiteverify.close(server)
      end
    end
  end

  defp option(input, {key, field}) do
    case Map.fetch(input, field) do
      {:ok, value} -> [{key, value}]
      :error -> []
    end
  end

  defp expect_outcome(%{"outcome" => "passed"} = expect, _secret, result) do
    assert {:ok, %Passed{} = passed} = result
    assert passed.challenge_ts == expect["challengeTs"]
    assert passed.hostname == expect["hostname"]
  end

  defp expect_outcome(%{"outcome" => "rejected"} = expect, _secret, result) do
    assert {:ok, %Rejected{} = rejected} = result
    assert rejected.error_codes == expect["errorCodes"]
  end

  defp expect_outcome(%{"outcome" => "unavailable"}, secret, result) do
    assert {:error, %UnavailableError{} = error} = result
    refute Exception.message(error) =~ secret
    refute inspect(error) =~ secret
  end

  defp expect_request(nil, server) do
    if server do
      assert LocalSiteverify.requests(server) == [], "no request arrives"
    end
  end

  defp expect_request(fields, server) do
    assert [received] = LocalSiteverify.requests(server), "one request arrives"
    assert received.method == "POST"
    assert received.path == "/siteverify"
    assert received.content_type == "application/x-www-form-urlencoded"
    assert received.form == fields
  end
end
