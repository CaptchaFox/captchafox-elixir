defmodule CaptchaFox.LocalSiteverify do
  @moduledoc false
  # A siteverify on the loopback interface that records every request it receives.

  defstruct [:listener, :port, :store]

  defmodule Received do
    @moduledoc false
    defstruct [:method, :path, :content_type, :form]
  end

  def answering(status, body, headers \\ []), do: start({:answer, status, body, headers})

  # Receives requests and never answers them while it runs.
  def silent, do: start(:silent)

  # Sends the status, the headers and the start of a body, then nothing more while it runs.
  def stalling(status, start), do: start({:stall, status, start})

  # Sends the status, the headers and the start of a body, then a space every 100 ms until the client goes.
  def trickling(status, start), do: start({:trickle, status, start})

  # Completes the connect only after about a second, when the client sends again a SYN that a full accept
  # queue dropped, and then never answers. Linux drops such a SYN.
  def connecting_slowly do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, backlog: 0])
    {:ok, port} = :inet.port(listener)
    fillers = fill(port, [])
    {:ok, store} = Agent.start_link(fn -> %{requests: [], handlers: [], broken_at: nil} end)

    handler =
      spawn(fn ->
        Process.sleep(300)

        # Frees a place in the queue for the SYN sent again; the connection itself is never accepted.
        {:ok, _filler} = :gen_tcp.accept(listener)
        Process.sleep(:infinity)
      end)

    Agent.update(store, &Map.merge(&1, %{handlers: [handler | &1.handlers], fillers: fillers}))
    %__MODULE__{listener: listener, port: port, store: store}
  end

  # An endpoint at a port of the loopback interface where nothing listens.
  def refusing_endpoint do
    {:ok, socket} = :gen_tcp.listen(0, ip: {127, 0, 0, 1})
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)
    "http://127.0.0.1:#{port}/siteverify"
  end

  def endpoint(%__MODULE__{port: port}), do: "http://127.0.0.1:#{port}/siteverify"

  def requests(%__MODULE__{store: store}), do: Agent.get(store, &Enum.reverse(&1.requests))

  # When a trickling server found the connection closed, by System.monotonic_time(:millisecond); nil while it is open.
  def broken_at(%__MODULE__{store: store}), do: Agent.get(store, & &1.broken_at)

  def close(%__MODULE__{listener: listener, store: store}) do
    :gen_tcp.close(listener)

    store |> Agent.get(&Map.get(&1, :fillers, [])) |> Enum.each(&:gen_tcp.close/1)
    store |> Agent.get(& &1.handlers) |> Enum.each(&Process.exit(&1, :kill))
    Agent.stop(store)
  end

  defp fill(port, fillers) do
    if length(fillers) > 20 do
      raise "the accept queue did not fill"
    end

    case :gen_tcp.connect({127, 0, 0, 1}, port, [active: false], 200) do
      {:ok, socket} -> fill(port, [socket | fillers])
      {:error, :timeout} -> fillers
    end
  end

  defp start(mode) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)
    {:ok, store} = Agent.start_link(fn -> %{requests: [], handlers: [], broken_at: nil} end)
    # The acceptor ends when close/1 closes the listener.
    spawn(fn -> accept(listener, mode, store) end)
    %__MODULE__{listener: listener, port: port, store: store}
  end

  defp accept(listener, mode, store) do
    case :gen_tcp.accept(listener) do
      {:ok, socket} ->
        handler =
          spawn(fn ->
            receive do
              :go -> serve(socket, mode, store)
            end
          end)

        :ok = :gen_tcp.controlling_process(socket, handler)
        Agent.update(store, &%{&1 | handlers: [handler | &1.handlers]})
        send(handler, :go)
        accept(listener, mode, store)

      {:error, _reason} ->
        :ok
    end
  end

  defp serve(socket, mode, store) do
    received = receive_request(socket)
    Agent.update(store, &%{&1 | requests: [received | &1.requests]})

    case mode do
      {:answer, status, body, headers} ->
        head(socket, status, [{"content-length", byte_size(body)} | headers])
        :ok = :gen_tcp.send(socket, body)
        :gen_tcp.close(socket)

      :silent ->
        Process.sleep(:infinity)

      {:stall, status, start} ->
        head(socket, status, [{"transfer-encoding", "chunked"}])
        :ok = :gen_tcp.send(socket, chunk(start))
        Process.sleep(:infinity)

      {:trickle, status, start} ->
        head(socket, status, [{"transfer-encoding", "chunked"}])
        :ok = :gen_tcp.send(socket, chunk(start))
        trickle(socket, store)
    end
  end

  defp trickle(socket, store) do
    Process.sleep(100)

    case :gen_tcp.send(socket, chunk(" ")) do
      :ok ->
        trickle(socket, store)

      {:error, _reason} ->
        now = System.monotonic_time(:millisecond)
        Agent.update(store, &%{&1 | broken_at: now})
    end
  end

  defp receive_request(socket) do
    :ok = :inet.setopts(socket, packet: :http_bin)
    {:ok, {:http_request, method, {:abs_path, path}, _version}} = :gen_tcp.recv(socket, 0, 5_000)
    headers = receive_headers(socket, %{})
    :ok = :inet.setopts(socket, packet: :raw)

    body =
      case String.to_integer(Map.get(headers, "content-length", "0")) do
        0 ->
          ""

        length ->
          {:ok, body} = :gen_tcp.recv(socket, length, 5_000)
          body
      end

    %Received{
      method: to_string(method),
      path: path,
      content_type: headers["content-type"],
      form: decode_form(body)
    }
  end

  defp receive_headers(socket, headers) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _, name, _, value}} ->
        receive_headers(socket, Map.put(headers, String.downcase(to_string(name)), value))

      {:ok, :http_eoh} ->
        headers
    end
  end

  defp decode_form(body) do
    body
    |> URI.query_decoder(:www_form)
    |> Enum.reduce(%{}, fn {name, value}, form ->
      if Map.has_key?(form, name) do
        raise "the field #{name} was sent twice"
      end

      Map.put(form, name, value)
    end)
  end

  defp head(socket, status, headers) do
    lines =
      for {name, value} <- [
            {"content-type", "application/json"},
            {"connection", "close"} | headers
          ],
          do: "#{name}: #{value}\r\n"

    :ok = :gen_tcp.send(socket, ["HTTP/1.1 #{status} Status\r\n", lines, "\r\n"])
  end

  defp chunk(data), do: [Integer.to_string(byte_size(data), 16), "\r\n", data, "\r\n"]
end
