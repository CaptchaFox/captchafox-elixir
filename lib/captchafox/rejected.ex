defmodule CaptchaFox.Rejected do
  @moduledoc """
  siteverify answered `"success": false`, or the token was empty.

  `error_codes` holds the error codes of siteverify, such as `"timeout-or-duplicate"`, possibly none.
  """

  defstruct error_codes: []

  @type t :: %__MODULE__{error_codes: [String.t()]}
end
