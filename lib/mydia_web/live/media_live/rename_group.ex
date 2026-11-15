defmodule MydiaWeb.MediaLive.RenameGroup do
  @moduledoc "A media item's file previews in a rename dialog."

  alias Mydia.Library.Structs.RenamePreview

  @enforce_keys [:media_item_id, :title, :previews]
  defstruct [:media_item_id, :title, :previews]

  @type t :: %__MODULE__{
          media_item_id: String.t() | nil,
          title: String.t() | nil,
          previews: [RenamePreview.t()]
        }
end
