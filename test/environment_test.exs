defmodule CaptchaFox.EnvironmentTest do
  # Stops :inets, which the whole VM shares, so it runs alone.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias CaptchaFox.{LocalSiteverify, UnavailableError}

  @moduletag timeout: 10_000

  @secret "ok_11111111000000001111111100000000"

  test "a crash of the HTTP client cannot be evaluated, without the secret key and without a log" do
    server = LocalSiteverify.answering(200, ~s({"success":true}))

    client = %{
      CaptchaFox.new(@secret, timeout: 2_000)
      | endpoint: LocalSiteverify.endpoint(server)
    }

    Process.flag(:trap_exit, true)
    capture_log(fn -> :ok = Application.stop(:inets) end)

    try do
      log =
        capture_log(fn ->
          assert {:error, %UnavailableError{} = error} = CaptchaFox.verify(client, "token")
          refute Exception.message(error) =~ @secret
          refute inspect(error) =~ @secret
        end)

      assert log == "", "the library logged #{inspect(log)}"
      assert Process.info(self(), :messages) == {:messages, []}
    after
      {:ok, _} = Application.ensure_all_started(:inets)
      LocalSiteverify.close(server)
    end
  end
end
