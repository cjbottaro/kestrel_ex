defmodule KestrelTest do
  use ExUnit.Case

  defmodule Client do
    use Kestrel,
      finch: KestrelTestFinch,
      url: "http://localhost:9200"
  end

  defmodule InitClient do
    use Kestrel, finch: KestrelTestFinch

    def init(config) do
      Keyword.put(config, :path, "/from-init")
    end
  end

  defmodule RuntimeUrlClient do
    use Kestrel, finch: KestrelTestFinch
  end

  setup do
    start_supervised!({Finch, name: KestrelTestFinch})
    :ok
  end

  test "config/0 reflects use options" do
    assert Client.config() == [finch: KestrelTestFinch, url: "http://localhost:9200"]
  end

  test "config/0 applies init/1 override" do
    assert InitClient.config() |> Keyword.get(:finch) == KestrelTestFinch
    assert InitClient.config() |> Keyword.get(:path) == "/from-init"
  end

  test "build/1 uses configured url and joins path" do
    req = Client.build(path: "/index")

    assert req.scheme == :http
    assert req.host == "localhost"
    assert req.port == 9200
    assert req.path == "/index"
    assert req.method == "GET"
  end

  test "build/1 accepts a URI struct for url" do
    req =
      RuntimeUrlClient.build(
        url: URI.parse("http://example.com:8080/api"),
        path: "/v1/users"
      )

    assert req.scheme == :http
    assert req.host == "example.com"
    assert req.port == 8080
    assert req.path == "/api/v1/users"
    assert req.method == "GET"
  end

  test "build/1 encodes map body as JSON and adds content-type header" do
    req = Client.build(body: %{foo: "bar"})

    assert req.body == ~s({"foo":"bar"})
    assert {"Content-Type", "application/json"} in req.headers
  end

  test "build/1 keeps non-map body unchanged" do
    req = Client.build(body: "raw-body", headers: [{"x-test", "1"}])

    assert req.body == "raw-body"
    assert req.headers == [{"x-test", "1"}]
  end

  test "request/2 accepts keyword opts and decodes JSON responses" do
    with_http_server(json_response(~s({"ok":true})), fn port ->
      resp = RuntimeUrlClient.request(url: "http://127.0.0.1:#{port}/json")

      assert resp.status == 200
      assert resp.body == %{"ok" => true}
    end)
  end

  test "request/2 accepts Finch.Request and preserves non-json body" do
    with_http_server(text_response("plain text"), fn port ->
      req = RuntimeUrlClient.build(url: "http://127.0.0.1:#{port}/text")
      resp = RuntimeUrlClient.request(req)

      assert resp.status == 200
      assert resp.body == "plain text"
    end)
  end

  test "stream/4 accepts keyword opts" do
    with_http_server(text_response("stream-body"), fn port ->
      result =
        RuntimeUrlClient.stream([url: "http://127.0.0.1:#{port}/stream"], "", fn
          {:data, data}, acc -> acc <> data
          _, acc -> acc
        end)

      assert result == {:ok, "stream-body"}
    end)
  end

  defp json_response(body) do
    "HTTP/1.1 200 OK\r\n" <>
      "content-type: application/json\r\n" <>
      "content-length: #{byte_size(body)}\r\n" <>
      "connection: close\r\n\r\n" <>
      body
  end

  defp text_response(body) do
    "HTTP/1.1 200 OK\r\n" <>
      "content-type: text/plain\r\n" <>
      "content-length: #{byte_size(body)}\r\n" <>
      "connection: close\r\n\r\n" <>
      body
  end

  defp with_http_server(raw_response, fun) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true])

    {:ok, {_addr, port}} = :inet.sockname(listener)

    server =
      spawn(fn ->
        case :gen_tcp.accept(listener) do
          {:ok, socket} ->
            _ = :gen_tcp.recv(socket, 0, 5_000)
            _ = :gen_tcp.send(socket, raw_response)
            _ = :gen_tcp.close(socket)
            _ = :gen_tcp.close(listener)

          {:error, :closed} ->
            :ok
        end
      end)

    try do
      fun.(port)
    after
      if Process.alive?(server), do: Process.exit(server, :normal)
      if Port.info(listener), do: :gen_tcp.close(listener)
    end
  end
end
