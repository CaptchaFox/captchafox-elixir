defmodule CaptchaFoxTest do
  # What the specification's cases leave out.
  use ExUnit.Case, async: true

  alias CaptchaFox.{LocalSiteverify, Passed, Rejected, UnavailableError}

  @moduletag timeout: 10_000

  @secret "ok_11111111000000001111111100000000"
  @timeout 2_000

  defp client(server, secret \\ @secret, timeout \\ @timeout) do
    %{CaptchaFox.new(secret, timeout: timeout) | endpoint: LocalSiteverify.endpoint(server)}
  end

  defp with_server(server, fun) do
    fun.(server)
  after
    LocalSiteverify.close(server)
  end

  test "fields arrive unchanged whatever their characters" do
    with_server(LocalSiteverify.answering(200, ~s({"success":true})), fn server ->
      secret = "ok_a+b&c=d %ä"
      token = "t+&=/?#% ä€"
      CaptchaFox.verify(client(server, secret), token, sitekey: "sk_1", remote_ip: "2001:db8::1")

      expected = %{
        "secret" => secret,
        "response" => token,
        "sitekey" => "sk_1",
        "remoteIp" => "2001:db8::1"
      }

      assert [%{form: ^expected}] = LocalSiteverify.requests(server)
    end)
  end

  test "a remote IP address as a tuple is sent as text" do
    with_server(LocalSiteverify.answering(200, ~s({"success":true})), fn server ->
      CaptchaFox.verify(client(server), "token", remote_ip: {203, 0, 113, 7})
      CaptchaFox.verify(client(server), "token", remote_ip: {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1})

      assert ["203.0.113.7", "2001:db8::1"] =
               Enum.map(LocalSiteverify.requests(server), & &1.form["remoteIp"])
    end)
  end

  test "a nil token is rejected without a request" do
    with_server(LocalSiteverify.answering(200, ~s({"success":true})), fn server ->
      assert {:ok, %Rejected{error_codes: ["missing-input-response"]}} =
               CaptchaFox.verify(client(server), nil)

      assert LocalSiteverify.requests(server) == []
    end)
  end

  test "a repeated success cannot be evaluated, whichever comes first" do
    for body <- [~s({"success":false,"success":true}), ~s({"success":true,"success":false})] do
      with_server(LocalSiteverify.answering(200, body), fn server ->
        assert {:error, %UnavailableError{}} = CaptchaFox.verify(client(server), "token")
      end)
    end
  end

  test "content after the JSON object cannot be evaluated" do
    with_server(
      LocalSiteverify.answering(200, ~s({"success":true} {"success":true})),
      fn server ->
        assert {:error, %UnavailableError{}} = CaptchaFox.verify(client(server), "token")
      end
    )
  end

  test "the default timeout is five seconds" do
    assert CaptchaFox.new(@secret).timeout == 5_000
  end

  test "the timeout ends an answer that never completes and closes the connection" do
    with_server(LocalSiteverify.trickling(200, ~s({"success":true)), fn server ->
      start = System.monotonic_time(:millisecond)

      assert {:error, %UnavailableError{}} =
               CaptchaFox.verify(client(server, @secret, 1_000), "token")

      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed < 1_500, "the verification took #{elapsed} ms"

      # The server notices the closed connection when it writes its next space.
      assert eventually(fn -> LocalSiteverify.broken_at(server) end, 5_000),
             "the connection is still open"
    end)
  end

  test "a redirect is not followed" do
    for status <- [301, 302, 303, 307, 308] do
      target = LocalSiteverify.answering(200, ~s({"success":true}))
      location = [{"location", LocalSiteverify.endpoint(target)}]

      with_server(LocalSiteverify.answering(status, "", location), fn server ->
        assert {:error, %UnavailableError{}} = CaptchaFox.verify(client(server), "token")
      end)

      assert LocalSiteverify.requests(target) == [], "the redirect #{status} was followed"
      LocalSiteverify.close(target)
    end
  end

  test "the timeout counts from the connect" do
    with_server(LocalSiteverify.connecting_slowly(), fn server ->
      start = System.monotonic_time(:millisecond)

      assert {:error, %UnavailableError{}} = CaptchaFox.verify(client(server), "token")
      elapsed = System.monotonic_time(:millisecond) - start
      assert elapsed < @timeout + 500, "the verification took #{elapsed} ms"
    end)
  end

  test "a verification leaves nothing in the mailbox of a caller that traps exits, and no link" do
    Process.flag(:trap_exit, true)
    passing = LocalSiteverify.answering(200, ~s({"success":true}))
    silent = LocalSiteverify.silent()
    {:links, links} = Process.info(self(), :links)

    assert {:ok, %Passed{}} = CaptchaFox.verify(client(passing), "token")

    assert {:error, %UnavailableError{}} =
             CaptchaFox.verify(client(silent, @secret, 300), "token")

    assert Process.info(self(), :messages) == {:messages, []}
    assert Process.info(self(), :links) == {:links, links}
    LocalSiteverify.close(passing)
    LocalSiteverify.close(silent)
  end

  test "the secret key is not in the inspected client" do
    refute inspect(CaptchaFox.new(@secret)) =~ @secret
  end

  test "an empty or no string secret key, no positive timeout or an unknown option is refused" do
    assert_raise ArgumentError, "the secret key is empty", fn -> CaptchaFox.new("") end

    assert_raise ArgumentError, "the secret key is no string", fn ->
      CaptchaFox.new(untyped(String.to_charlist(@secret)))
    end

    assert_raise ArgumentError, fn -> CaptchaFox.new(@secret, timeout: 0) end
    assert_raise ArgumentError, fn -> CaptchaFox.new(@secret, timeout: 1.5) end
    assert_raise ArgumentError, fn -> CaptchaFox.new(@secret, timout: 1_000) end
  end

  test "a refused argument names no value" do
    client = CaptchaFox.new(@secret)
    ip = "203.0.113.7"

    for call <- [
          fn -> CaptchaFox.new(@secret, untyped(@secret)) end,
          fn -> CaptchaFox.new(@secret, secret: @secret) end,
          fn -> CaptchaFox.verify(client, "token", remoteip: ip) end,
          fn -> CaptchaFox.verify(client, untyped(%{"a" => ip}), remote_ip: ip) end,
          fn ->
            CaptchaFox.verify(client, "token", remote_ip: untyped(ip <> "x") |> to_charlist())
          end,
          fn -> CaptchaFox.verify(untyped(%{secret: @secret}), "token", remote_ip: ip) end
        ] do
      error = assert_raise ArgumentError, call
      refute Exception.message(error) =~ @secret
      refute Exception.message(error) =~ ip
    end
  end

  # Hides the type of a wrong argument passed on purpose from the type checker of Elixir 1.20.
  defp untyped(value), do: Process.get(:untyped, value)

  defp eventually(fun, remaining) do
    case fun.() do
      nil when remaining > 0 ->
        Process.sleep(50)
        eventually(fun, remaining - 50)

      value ->
        value
    end
  end
end
