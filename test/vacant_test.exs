defmodule VacantTest do
  use ExUnit.Case
  doctest Vacant

  test "greets the world" do
    assert Vacant.hello() == :world
  end
end
