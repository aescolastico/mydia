defmodule Mydia.Downloads.PriorityTest do
  use ExUnit.Case, async: true

  alias Mydia.Downloads.Priority

  describe "all/0" do
    test "returns the canonical 5-tier taxonomy, ordered low to high" do
      assert Priority.all() == [:verylow, :low, :normal, :high, :veryhigh]
    end

    test "regression guard against accidental atom additions or removals" do
      # Every entry must be one of the recognised priority atoms.
      Enum.each(Priority.all(), fn atom ->
        assert atom in [:verylow, :low, :normal, :high, :veryhigh]
      end)

      # And the list length is exactly 5.
      assert length(Priority.all()) == 5
    end
  end

  describe "default/0" do
    test "is :normal" do
      assert Priority.default() == :normal
    end

    test "is itself a valid priority" do
      assert Priority.valid?(Priority.default())
    end
  end

  describe "valid?/1" do
    test "returns true for every member of all/0" do
      Enum.each(Priority.all(), fn atom ->
        assert Priority.valid?(atom), "expected #{inspect(atom)} to be valid"
      end)
    end

    test "returns false for unknown atoms, strings, numbers, and nil" do
      refute Priority.valid?(:turbo)
      refute Priority.valid?("high")
      refute Priority.valid?(1)
      refute Priority.valid?(nil)
    end
  end

  describe "resolve/3" do
    test "returns the default when the profile is empty" do
      assert Priority.resolve(:high, %{}, "1") == "1"
      assert Priority.resolve(:low, %{}, "-1") == "-1"
      assert Priority.resolve(:normal, %{}, "0") == "0"
    end

    test "returns the profile override when present (string keys)" do
      profile = %{"high" => "2", "low" => "-100"}
      assert Priority.resolve(:high, profile, "1") == "2"
      assert Priority.resolve(:low, profile, "-1") == "-100"
    end

    test "falls back to default for atoms not present in the profile" do
      profile = %{"high" => "2"}
      assert Priority.resolve(:low, profile, "-1") == "-1"
      assert Priority.resolve(:normal, profile, "0") == "0"
    end

    test "nil priority returns the default" do
      assert Priority.resolve(nil, %{"high" => "2"}, "0") == "0"
    end

    test "unknown atoms return the default" do
      assert Priority.resolve(:turbo, %{"turbo" => "9"}, "0") == "0"
    end

    test "works with integer values (e.g. NZBGet's domain)" do
      profile = %{"high" => 75, "veryhigh" => 100}
      assert Priority.resolve(:high, profile, 50) == 75
      assert Priority.resolve(:veryhigh, profile, 100) == 100
      assert Priority.resolve(:low, profile, -50) == -50
    end
  end
end
