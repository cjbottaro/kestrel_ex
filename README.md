# Kestrel

Small conveniences for building `Finch` clients.

`Kestrel` gives you a lightweight `use`-based client module with:

- `config/0`
- `build/1`
- `request/2`
- `stream/4`

It also JSON-encodes map request bodies automatically and adds a JSON content type header.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `kestrel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kestrel, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/kestrel>.

## Usage

```elixir
defmodule Github.GraphQL do
  use Kestrel,
    finch: MyFinch,
    url: "https://api.github.com/graphql"

  def query(query_string) do
    request(method: :post, body: %{query: query_string})
  end
end
```

Build only:

```elixir
req = Github.GraphQL.build(path: "/")
```

Execute:

```elixir
resp = Github.GraphQL.request(path: "/", method: :get)
```
