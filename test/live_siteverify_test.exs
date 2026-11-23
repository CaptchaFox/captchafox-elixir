defmodule CaptchaFox.LiveSiteverifyTest do
  # Verifies the public test keys against CaptchaFox's siteverify; needs the network.
  use ExUnit.Case, async: true

  alias CaptchaFox.{Passed, Rejected}

  @moduletag :live

  @passing_secret "ok_11111111000000001111111100000000"
  @failing_secret "ok_FFFFFFFF00000000FFFFFFFF00000000"
  @sitekey "sk_11111111000000001111111100000000"
  @token "11111111000000001111111100000000"

  test "the test key passes" do
    assert {:ok, %Passed{}} = CaptchaFox.verify(CaptchaFox.new(@passing_secret), @token)
  end

  test "the test key passes with sitekey and remote IP address" do
    client = CaptchaFox.new(@passing_secret)

    assert {:ok, %Passed{}} =
             CaptchaFox.verify(client, @token, sitekey: @sitekey, remote_ip: "203.0.113.7")
  end

  test "the failing test key is rejected" do
    assert {:ok, %Rejected{error_codes: ["timeout-or-duplicate"]}} =
             CaptchaFox.verify(CaptchaFox.new(@failing_secret), @token)
  end
end
