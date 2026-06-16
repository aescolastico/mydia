defmodule Mydia.HooksRemovedTest do
  @moduledoc """
  Guards the U11 removal of the Luerl hooks system: the modules and dependency
  are gone, and the behavior they backed (acting on a newly added media item) now
  flows through the plugin dispatcher's `media_item.added` event instead.
  """
  use Mydia.DataCase, async: false

  import Mydia.MediaFixtures

  alias Phoenix.PubSub

  test "the Mydia.Hooks modules no longer exist" do
    refute Code.ensure_loaded?(Mydia.Hooks)
    refute Code.ensure_loaded?(Mydia.Hooks.Manager)
    refute Code.ensure_loaded?(Mydia.Hooks.Executor)
  end

  test "the :luerl dependency is gone" do
    refute List.keymember?(Application.loaded_applications(), :luerl, 0)
  end

  test "adding a media item still emits media_item.added on the bus the dispatcher consumes" do
    PubSub.subscribe(Mydia.PubSub, "events:all")

    item = media_item_fixture(%{title: "Arrival"})

    assert_receive {:event_created, %{type: "media_item.added", resource_id: resource_id}},
                   1_000

    assert resource_id == item.id
  end
end
