defmodule KestrelTest do
  use ExUnit.Case
  doctest Kestrel

  test "greets the world" do
    assert Kestrel.hello() == :world
  end
end
