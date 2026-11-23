defmodule CaptchaFox.Passed do
  @moduledoc """
  siteverify answered `"success": true`.

  `challenge_ts` is the time of the challenge as an ISO 8601 timestamp and `hostname` the hostname of the site
  where the challenge was solved, each `nil` where siteverify did not send it.
  """

  defstruct [:challenge_ts, :hostname]

  @type t :: %__MODULE__{challenge_ts: String.t() | nil, hostname: String.t() | nil}
end
