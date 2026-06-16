defmodule MydiaQualityTest do
  use ExUnit.Case, async: true

  # MydiaQuality is loaded by mix.exs (Code.require_file "mix_quality.ex"),
  # so it is already available in the VM when these tests run.

  defmodule SampleBehaviour do
    @moduledoc false
    @callback do_work(arg :: term()) :: term()
    @callback ping() :: :pong
  end

  defmodule SampleImpl do
    @moduledoc false
    @behaviour SampleBehaviour

    @impl true
    def do_work(arg), do: arg

    @impl true
    def ping, do: :pong

    # Exported but NOT a behaviour callback.
    def helper(x), do: x
  end

  defmodule PlainModule do
    @moduledoc false
    # Name collides with a callback, but this module declares no behaviour.
    def do_work(arg), do: arg
  end

  describe "behaviour_callback?/1" do
    test "recognises a behaviour callback implementation" do
      assert MydiaQuality.behaviour_callback?({SampleImpl, :do_work, 1})
      assert MydiaQuality.behaviour_callback?({SampleImpl, :ping, 0})
    end

    test "does not match a non-callback export on a behaviour module" do
      refute MydiaQuality.behaviour_callback?({SampleImpl, :helper, 1})
    end

    test "does not match a name/arity that only coincides with a callback" do
      refute MydiaQuality.behaviour_callback?({PlainModule, :do_work, 1})
    end

    test "does not match the right name at the wrong arity" do
      refute MydiaQuality.behaviour_callback?({SampleImpl, :do_work, 2})
    end

    test "returns false for an unloadable module instead of raising" do
      refute MydiaQuality.behaviour_callback?({Does.Not.Exist, :foo, 0})
    end
  end
end
