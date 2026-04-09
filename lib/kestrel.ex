defmodule Kestrel do
  @moduledoc ~S"""
  A small client wrapper around `Finch`.

  `use Kestrel` injects a tiny client module with:

  - `config/0`: returns module config after `init/1`
  - `build/1`: builds a `%Finch.Request{}`
  - `request/2`: executes a request (from a `%Finch.Request{}` or keyword opts)
  - `stream/4`: streams a request (from a `%Finch.Request{}` or keyword opts)

  Request options are read from module config first, then per-request opts:

  - `:finch` (required): Finch pool name
  - `:url`: base URL
  - `:path`: path joined onto `:url`
  - `:method`: HTTP method (default `:get`)
  - `:headers`: request headers (default `[]`)
  - `:body`: request body (default `""`)

  If `:body` is a map, Kestrel JSON-encodes it with `Jason.encode!/1` and prepends
  `{"Content-Type", "application/json"}` to headers.

  ## Quickstart

  Assuming your application's supervision tree has a `Finch` pool like:

      children = [
        {Finch, name: MyFinch}
      ]

  Define a client:

      defmodule Github.GraphQL do
        use Kestrel,
          finch: MyFinch,
          url: "https://api.github.com/graphql"

        def query(query_string, opts \\ []) do
          request(
            [method: :post, body: %{query: query_string}] ++ opts
          )
        end
      end

  Build requests without executing them:

      iex> req = Github.GraphQL.build(path: "/")
      iex> req.method
      :get
      iex> req.path
      "/"

  Automatically encode JSON bodies:

      iex> req = Github.GraphQL.build(body: %{query: "{ viewer { login } }"})
      iex> req.body
      "{\"query\":\"{ viewer { login } }\"}"
      iex> {"Content-Type", "application/json"} in req.headers
      true

  Execute requests with a built request or keyword opts:

      Github.GraphQL.request(method: :post, body: %{query: "{ viewer { login } }"})
  """

  @doc """
  Returns the module configuration.

  The result is the options provided to `use Kestrel` after passing through `c:init/1`.

      defmodule EsClient do
        use Kestrel, finch: MyFinch

        def init(config) do
          Keyword.put(config, :path, "/bar")
        end
      end

      iex> EsClient.config()
      [finch: MyFinch, path: "/bar"]
  """
  @callback config() :: Keyword.t()

  @doc """
  Builds a `%Finch.Request{}` from options and module config.

  Keys are read in this order: module config first, then request opts, then defaults.
  """
  @callback build(opts :: Keyword.t()) :: Finch.Request.t()

  @doc """
  Executes a request.

  Accepts either:

  - a `%Finch.Request{}`
  - keyword request options (forwarded through `build/1` first)

  `opts` is passed through to `Finch.request/3`.
  """
  @callback request(req :: Finch.Request.t() | Keyword.t(), opts :: Finch.request_opts()) ::
              Finch.Response.t()

  @doc """
  Streams a request via `Finch.stream/5`.

  Accepts either:

  - a `%Finch.Request{}`
  - keyword request options (forwarded through `build/1` first)
  """
  @callback stream(
              req :: Finch.Request.t() | Keyword.t(),
              acc :: term(),
              fun :: (term(), term() -> term()),
              opts :: Finch.request_opts()
            ) :: term()

  @doc false
  @callback init(config :: Keyword.t()) :: Keyword.t()

  defmacro __using__(config \\ []) do
    quote [location: :keep] do
      @behaviour Kestrel

      @config unquote(config)

      def config do
        init(@config)
      end

      def build(req \\ []) do
        config  = config()

        url     = get_config(config, req, :url, "")
        path    = get_config(config, req, :path, nil)
        body    = get_config(config, req, :body, "")
        method  = get_config(config, req, :method, :get)
        headers = get_config(config, req, :headers, [])

        url = if path do
          uri = case url do
            %URI{} = uri -> uri
            uri when is_binary(uri) -> URI.parse(url)
          end
          %URI{uri | path: Path.join(uri.path || "/", path)}
        else
          url
        end

        {headers, body} = if is_map(body) do
          {
            [{"Content-Type", "application/json"} | headers],
            Jason.encode!(body)
          }
        else
          {headers, body}
        end

        Finch.build(method, url, headers, body)
      end

      def request(req, opts \\ [])

      def request(%Finch.Request{} = req, opts) do
        case Finch.request(req, config()[:finch], opts) do
          {:ok, %Finch.Response{} = resp} ->
            json? =
              Enum.any?(resp.headers, fn {key, value} ->
                String.downcase(key) == "content-type" and
                  String.contains?(String.downcase(value), "application/json")
              end)

            if json? do
              %Finch.Response{resp | body: Jason.decode!(resp.body)}
            else
              resp
            end

          {:error, error} ->
            raise error
        end
      end

      def request(req, opts) when is_list(req) do
        build(req) |> request(opts)
      end

      def stream(req, acc, fun, opts \\ [])

      def stream(%Finch.Request{} = req, acc, fun, opts) do
        Finch.stream(req, config()[:finch], acc, fun, opts)
      end

      def stream(req, acc, fun, opts) do
        build(req) |> stream(acc, fun, opts)
      end

      def init(config), do: config
      defoverridable(init: 1)

      defp get_config(config, opts, key, default \\ nil) do
        config[key] || opts[key] || default
      end
    end
  end

end
