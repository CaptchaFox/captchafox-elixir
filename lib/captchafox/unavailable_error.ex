defmodule CaptchaFox.UnavailableError do
  @moduledoc """
  siteverify could not be evaluated: it was not reached, did not answer in time, answered with an HTTP status
  other than 200, or with a body that is no JSON object with a boolean `success`.

  Whether the protected request passes then is the caller's decision. The message never contains the secret key.
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}
end
