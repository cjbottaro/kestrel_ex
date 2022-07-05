defmodule Kestrel do
  @moduledoc ~S"""
  Conveniences for working with `Finch`.

  This module provides some conveniences inspired by `HTTPoison.Base` as well some other
  things like automatic JSON encoding/decoding and a more robust API.

  ## Quickstart

  Assuming your application's supervision tree has a `Finch` pool like:

      children = [
        {Finch, name: MyFinch}
      ]

  Then you can use that pool with `Kestrel`:

      defmodule Github.GraphQL do
        use Kestrel,
          finch: MyFinch
          url: "https://api.github.com/graphql"

        def process_request_headers(headers) do
          token = Application.get_env(:my_app, :github_token)
          [{"Authorization", "Bearer #{token}"} | headers]
        end

        def query(q) do
          post(body: %{query: q})
        end
      end

      iex> Github.GraphQL.query("{ viewer { login } }")
      {:ok, %Finch.Response{body: %{"data" => %{"viewer" => %{"login" => "cjbottaro"}}}, ...}}

  ## Automatic JSON processing

  If a request body is a map, then it is automatically encoded with `Jason.encode!/2` and a
  header for content type is added.

      iex> MyClient.build(url: "https://foo.bar.com/blah", body: %{foo: "bar"})
      %Finch.Request{
        body: "{\"foo\":\"bar\"}",
        headers: [{"Content-Type", "application/json"}],
        host: "foo.bar.com",
        method: "GET",
        path: "/blah",
        port: 443,
        private: %{},
        query: nil,
        scheme: :https,
        unix_socket: nil
      }

  Similarly, if a response has a header for content type `application/json`, then the body
  is replaced with the results from `Jason.decode!/2`.
  """

  @type request_body :: Finch.Request.body | map

  @doc """
  Get configuration options.

  Config from `Config` takes precedence over `use` arguments so that runtime
  config works properly.

      import Config

      config :my_app, EsClient, url: "http://staging-es.foo.com"

      defmodule EsClient do
        use Kestrel, finch: MyFinch
      end

      iex> EsClient.config
      [finch: MyFinch, url: "http://staging-es.foo.com"]

  """
  @callback config :: Keyword.t

  @doc """
  Like `Finch.build/5`.

  Like `Finch.build/5`, but runs all the `process_request_*` callbacks and also
  automatically handles JSON.
  """
  @callback build(method :: Finch.Request.method, url :: Finch.Request.url, headers :: Finch.Request.headers, body :: request_body, opts :: Keyword.t) :: Finch.Request.t

  @doc """
  An alternative to `c:build/5` that takes a keyword list.

  Valid keys are...

    * `:method` - `t:Finch.Request.method/0` (default: `:get`)
    * `:url` - `t:Finch.Request.url/0` (default: `nil`)
    * `:query` - `t:Enum.t/0` (default: `[]`)
    * `:headers` - `t:Finch.Request.headers/0` (default: `[]`)
    * `:body` - `t:request_body/0` (default: `nil`)

  All other keys are passed as `opts` to `Finch.build/5`.

  ## Examples

      MyClient.build(
        url: "https://some.api.com/v2",
        query: [user_id: 123, debug: true]
      )

      MyClient.build(
        method: :post,
        url: "https://some.api.com/v2",
        query: [user_id: 123],
        body: %{
          name: "Genevieve",
          age: 4
        }
      )

  """
  @callback build(opts :: Keyword.t) :: Finch.Request.t

  @doc """
  Build a GET request.

  The implementation of this callback has default args like:

      def build_get(url \\\\ nil, opts \\\\ [])

  And any combination of `url` and `opts` works...

      build_get()                                # neither opts nor url
      build_get("/foo/bar")                      # url, but no opts
      build_get(body: %{foo: "bar"})             # opts, but no url
      build_get("/foo/bar", body: %{foo: "bar"}) # Both url and opts

  Note that the `url` argument (if given) will supercede `opts[:url]`.
  """
  @callback build_get(url :: Finch.Request.url, opts :: Keyword.t) :: Finch.Request.t

  @doc """
  Like `Finch.request/3`.

  Applies `process_response_*` callbacks and also automatically decodes JSON responses.

  `opts` is passed through to `Finch.request/3`.
  """
  @callback request(req :: Finch.Request.t, opts :: Keyword.t) :: {:ok, Finch.Response.t} | {:error, Exception.t}

  @callback process_request_url(Finch.Request.url) :: Finch.Request.url
  @callback process_request_query(query :: map) :: Enum.t
  @callback process_request_headers(Finch.Request.headers) :: Finch.Request.headers
  @callback process_request_body(body :: request_body) :: request_body
  @callback process_response_body(body :: binary | map) :: any

  defmacro __using__(config \\ []) do
    quote [location: :keep] do
      @behaviour Kestrel

      @config unquote(config)

      def config do
        otp_app = case @config[:otp_app] do
          nil -> Kestrel.OtpAppCache.get(__MODULE__)
          otp_app -> otp_app
        end

        config = Application.get_env(otp_app, __MODULE__, [])

        Keyword.merge(@config, config)
      end

      def build(method, url, headers \\ [], body \\ [], opts \\ []) do
        Keyword.merge(opts, method: method, url: url, headers: headers, body: body)
        |> build()
      end

      def build(opts \\ []) do
        Kestrel.build(__MODULE__, opts)
      end

      def build_get(url \\ nil, opts \\ []),    do: Kestrel.build(__MODULE__, :get,    url, opts)
      def build_post(url \\ nil, opts \\ []),   do: Kestrel.build(__MODULE__, :post,   url, opts)
      def build_put(url \\ nil, opts \\ []),    do: Kestrel.build(__MODULE__, :put,    url, opts)
      def build_patch(url \\ nil, opts \\ []),  do: Kestrel.build(__MODULE__, :patch,  url, opts)
      def build_delete(url \\ nil, opts \\ []), do: Kestrel.build(__MODULE__, :delete, url, opts)
      def build_head(url \\ nil, opts \\ []),   do: Kestrel.build(__MODULE__, :head,   url, opts)

      def get(url \\ nil, opts \\ []),    do: build_get(url, opts)    |> request(opts)
      def post(url \\ nil, opts \\ []),   do: build_post(url, opts)   |> request(opts)
      def put(url \\ nil, opts \\ []),    do: build_put(url, opts)    |> request(opts)
      def patch(url \\ nil, opts \\ []),  do: build_patch(url, opts)  |> request(opts)
      def delete(url \\ nil, opts \\ []), do: build_delete(url, opts) |> request(opts)
      def head(url \\ nil, opts \\ []),   do: build_head(url, opts)   |> request(opts)

      def request(req, opts \\ []) do
        Kestrel.request(__MODULE__, req, opts)
      end

      def stream(req, acc, fun, opts \\ []) do
        Finch.stream(req, __MODULE__, acc, fun, opts)
      end

      def process_request_url(url), do: url
      defoverridable(process_request_url: 1)

      def process_request_query(query), do: query
      defoverridable(process_request_query: 1)

      def process_request_headers(headers), do: headers
      defoverridable(process_request_headers: 1)

      def process_request_body(body), do: body
      defoverridable(process_request_body: 1)

      def process_response_body(body), do: body
      defoverridable(process_response_body: 1)

    end
  end

  @doc false
  def build(mod, method, url, opts) do

    # Have to account for these combos...
    #   build(nil, [])
    #   build("/foo/bar", [])
    #   build(url: "/foo/bar", []) # This is the problematic one.
    #   build("/foo/bar", body: %{blah: "test"})
    {url, opts} = case {url, opts} do
      {url, []} when is_list(url) -> {nil, url}
      {url, opts} -> {url, opts}
    end

    opts = Keyword.put(opts, :method, method)

    opts = if url do
      Keyword.put(opts, :url, url)
    else
      opts
    end

    build(mod, opts)
  end

  @doc false
  def build(mod, opts \\ []) do
    method  = Keyword.get(opts, :method, :get)
    url     = Keyword.get(opts, :url, "")
    query   = Keyword.get(opts, :query, [])
    headers = Keyword.get(opts, :headers, [])
    body    = Keyword.get(opts, :body, nil)

    config = mod.config()

    uri = Path.join(config[:url], url)
    |> mod.process_request_url()
    |> URI.parse()

    query = URI.decode_query(uri.query || "")
    |> Map.merge(Map.new(query))
    |> mod.process_request_query()
    |> URI.encode_query()

    uri = if query == "" do
      %{uri | query: nil}
    else
      %{uri | query: query}
    end

    headers = mod.process_request_headers(headers)
    body = mod.process_request_body(body)
    {headers, body} = process_json_request(headers, body)

    Finch.build(method, uri, headers, body, opts)
  end

  @doc false
  def request(mod, req, opts) do
    config = mod.config()

    case Finch.request(req, config[:finch], opts) do
      {:ok, resp} -> {:ok, process_response(mod, resp)}
      error -> error
    end
  end

  defp process_json_request(headers, body) when is_map(body) do
    {
      [{"Content-Type", "application/json"} | headers],
      Jason.encode!(body)
    }
  end
  defp process_json_request(headers, body), do: {headers, body}

  defp is_response_json?(resp) do
    Enum.any?(resp.headers, fn {k, v} ->
      if String.downcase(k) == "content-type" do
        String.downcase(v) |> String.contains?("application/json")
      else
        false
      end
    end)
  end

  defp process_response(mod, resp) do
    body = if is_response_json?(resp) do
      Jason.decode!(resp.body)
    else
      resp.body
    end
    |> mod.process_response_body()

    %{resp | body: body}
  end

end
