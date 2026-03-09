defmodule MiraiTest do
  use ExUnit.Case
  doctest Mirai

  test "greets the world" do
    assert Mirai.hello() == :world
  end
end
