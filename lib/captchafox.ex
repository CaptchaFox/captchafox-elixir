defmodule CaptchaFox do
  @moduledoc """
  Verifies tokens of the CaptchaFox widget with siteverify, with the secret key of a site.

  Create a client once with `new/2` and reuse it; it holds no process and can be shared freely.
  """

  alias CaptchaFox.{Passed, Rejected, UnavailableError}

  @endpoint "https://api.captchafox.com/siteverify"
  @default_timeout 5_000

  # The secret key stays out of inspect, so that it never reaches a log through the client.
  @derive {Inspect, only: [:timeout]}
  @enforce_keys [:secret, :timeout, :endpoint]
  defstruct [:secret, :timeout, :endpoint]

  @opaque t :: %__MODULE__{secret: String.t(), timeout: pos_integer(), endpoint: String.t()}

  @type outcome :: {:ok, Passed.t() | Rejected.t()} | {:error, UnavailableError.t()}

  @type verify_option ::
          {:sitekey, String.t() | nil} | {:remote_ip, String.t() | :inet.ip_address() | nil}

  @doc """
  Creates a client with the secret key of the site.

  ## Options

    * `:timeout` - how long a verification may take in milliseconds, from connecting to siteverify
      to the end of its answer. Defaults to 5000.

  Raises `ArgumentError` if the secret key is empty or no string, or the timeout is no positive integer.
  """
  @spec new(String.t(), timeout: pos_integer()) :: t()
  def new(secret, opts \\ []) do
    # The arguments are checked in the body: a guard would print them, the secret among them, in a
    # FunctionClauseError.
    if not is_binary(secret) do
      raise ArgumentError, "the secret key is no string"
    end

    if secret == "" do
      raise ArgumentError, "the secret key is empty"
    end

    timeout = Keyword.get(options!(opts, [:timeout]), :timeout, @default_timeout)

    if not (is_integer(timeout) and timeout > 0) do
      raise ArgumentError, "the timeout is no positive integer of milliseconds"
    end

    %__MODULE__{secret: secret, timeout: timeout, endpoint: @endpoint}
  end

  @doc """
  Verifies a token.

  Returns `{:ok, %CaptchaFox.Passed{}}` or `{:ok, %CaptchaFox.Rejected{}}` when siteverify evaluated
  the token, and `{:error, %CaptchaFox.UnavailableError{}}` when siteverify cannot be evaluated.
  An empty or `nil` token is rejected with `missing-input-response` without a request.

  ## Options

    * `:sitekey` - the site key the token was issued for; not sent when `nil` or empty.
    * `:remote_ip` - the IP address of the visitor, as a string or a tuple such as `conn.remote_ip`;
      not sent when `nil` or empty.

  Raises `ArgumentError` if an argument has the wrong type, and `RuntimeError` if the operating system
  provides no CA certificates to check the certificate of siteverify with.
  """
  @spec verify(t(), String.t() | nil, [verify_option()]) :: outcome()
  def verify(client, token, opts \\ []) do
    # Checked in the body, so that no error message prints the token or the visitor's IP address.
    if not is_struct(client, __MODULE__) do
      raise ArgumentError, "the client is no %CaptchaFox{}"
    end

    if not (is_binary(token) or is_nil(token)) do
      raise ArgumentError, "the token is no string"
    end

    opts = options!(opts, [:sitekey, :remote_ip])
    sitekey = sitekey(opts[:sitekey])
    remote_ip = address(opts[:remote_ip])

    if token in [nil, ""] do
      {:ok, %Rejected{error_codes: ["missing-input-response"]}}
    else
      form =
        [
          {"secret", client.secret},
          {"response", token},
          {"sitekey", sitekey},
          {"remoteIp", remote_ip}
        ]
        |> Enum.reject(fn {_name, value} -> value in [nil, ""] end)
        |> URI.encode_query(:www_form)

      client |> post(form) |> evaluate(client.timeout)
    end
  end

  # Keyword.validate!/2 would print the values of the options, such as the secret key or an IP address.
  defp options!(opts, allowed) do
    if not (is_list(opts) and Enum.all?(opts, &match?({key, _value} when is_atom(key), &1))) do
      raise ArgumentError, "the options are no keyword list"
    end

    unknown = Keyword.keys(opts) -- allowed

    if unknown != [] do
      raise ArgumentError,
            "unknown options #{inspect(unknown)}, the allowed options are #{inspect(allowed)}"
    end

    opts
  end

  defp sitekey(sitekey) when is_binary(sitekey) or is_nil(sitekey), do: sitekey
  defp sitekey(_sitekey), do: raise(ArgumentError, "the sitekey is no string")

  defp address(ip) when is_binary(ip) or is_nil(ip), do: ip

  defp address(ip) do
    case is_tuple(ip) and :inet.ntoa(ip) do
      chars when is_list(chars) -> List.to_string(chars)
      _ -> raise ArgumentError, "the remote_ip is no IP address"
    end
  end

  defp post(client, form) do
    request =
      {String.to_charlist(client.endpoint), [], ~c"application/x-www-form-urlencoded", form}

    http_options = [
      timeout: client.timeout,
      connect_timeout: client.timeout,
      autoredirect: false,
      ssl: [
        verify: :verify_peer,
        cacerts: cacerts(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)],
        # The handshake's failure is the outcome; ssl would log it besides.
        log_level: :none
      ]
    ]

    # The request runs in a process of its own that is monitored, not linked, and hands its result over
    # in its exit reason: the caller's mailbox stays empty, and a crash of :httpc, whose reason holds the
    # request with the secret key, never leaves the library. The deadline also covers the connect, which
    # the timeout of :httpc does not before OTP 27.2.
    {pid, monitor} =
      spawn_monitor(fn ->
        result =
          try do
            :httpc.request(:post, request, http_options, body_format: :binary)
          catch
            _kind, _reason -> {:error, :http_client_failed}
          end

        exit({:shutdown, {:result, result}})
      end)

    receive do
      {:DOWN, ^monitor, :process, ^pid, {:shutdown, {:result, result}}} -> result
      {:DOWN, ^monitor, :process, ^pid, _reason} -> {:error, :http_client_failed}
    after
      client.timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(monitor, [:flush])
        {:error, :timeout}
    end
  end

  # A host without CA certificates is a fault of its setup, not an outage of siteverify, so it raises.
  defp cacerts do
    :public_key.cacerts_get()
  rescue
    _error -> raise "the operating system provides no CA certificates to check siteverify with"
  end

  defp evaluate({:ok, {{_version, 200, _reason}, _headers, body}}, _timeout) do
    case decode(body) do
      {:ok, %{"success" => true} = answer} ->
        {:ok,
         %Passed{
           challenge_ts: string(answer["challenge_ts"]),
           hostname: string(answer["hostname"])
         }}

      {:ok, %{"success" => false} = answer} ->
        {:ok, %Rejected{error_codes: strings(answer["error-codes"])}}

      {:ok, %{}} ->
        unavailable("siteverify answered without a boolean success")

      {:ok, _} ->
        unavailable("siteverify answered with JSON that is no object")

      :error ->
        unavailable("siteverify answered with a body that is no JSON")
    end
  end

  defp evaluate({:ok, {{_version, status, _reason}, _headers, _body}}, _timeout) do
    unavailable("siteverify answered with HTTP status #{status}")
  end

  defp evaluate({:error, :timeout}, timeout) do
    unavailable("siteverify did not answer within #{timeout} ms")
  end

  defp evaluate({:error, reason}, _timeout) do
    unavailable("siteverify could not be reached" <> cause(reason))
  end

  # Only reasons that cannot hold the request are named.
  defp cause({:failed_connect, details}) when is_list(details) do
    case List.keyfind(details, :inet, 0) do
      {:inet, _options, reason} -> cause(reason)
      _ -> ""
    end
  end

  defp cause({:tls_alert, {alert, _description}}) when is_atom(alert), do: ": TLS alert #{alert}"
  defp cause(reason) when is_atom(reason), do: ": #{reason}"
  defp cause(_reason), do: ""

  defp unavailable(message), do: {:error, %UnavailableError{message: message}}

  defp decode(body) do
    case JSON.decode(body, :ok, object_finish: &unique_object/2) do
      {value, :ok, ""} -> {:ok, value}
      _ -> :error
    end
  catch
    :repeated_member -> :error
  end

  # A repeated member, such as "success" twice, has no defined meaning, so the answer is no valid JSON object.
  defp unique_object(members, acc) do
    object = Map.new(members)

    if map_size(object) != length(members) do
      throw(:repeated_member)
    end

    {object, acc}
  end

  defp string(value) when is_binary(value), do: value
  defp string(_value), do: nil

  # A rejection stays a rejection when its error codes are malformed; only the entries that are strings are kept.
  defp strings(values) when is_list(values), do: Enum.filter(values, &is_binary/1)
  defp strings(_values), do: []
end
