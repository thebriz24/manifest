defmodule ManifestTest do
  use ExUnit.Case
  doctest Manifest

  test "greets the world" do
    assert Manifest.hello() == :world
  end
end
