defmodule Mydia.Plugins.Index.Entry do
  @moduledoc """
  A single plugin listing in an index/source catalog (U7).

  An entry pairs distribution metadata (where to download the package and the
  integrity hash to verify it against) with the plugin's embedded manifest, so
  the install UI can present the declared capabilities for approval *before* the
  package is downloaded.
  """

  alias Mydia.Plugins.Manifest

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          version: String.t(),
          description: String.t() | nil,
          author: String.t() | nil,
          package_url: String.t(),
          integrity: String.t(),
          manifest: Manifest.t(),
          source_url: String.t() | nil
        }

  @enforce_keys [:slug, :name, :version, :package_url, :integrity, :manifest]
  defstruct slug: nil,
            name: nil,
            version: nil,
            description: nil,
            author: nil,
            package_url: nil,
            integrity: nil,
            manifest: nil,
            source_url: nil
end
