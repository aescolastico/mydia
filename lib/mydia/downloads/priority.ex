defmodule Mydia.Downloads.Priority do
  @moduledoc """
  Five-tier download priority taxonomy used by `Mydia.Downloads.Queue` and the
  per-adapter `add_torrent/3` callbacks.

  Each adapter resolves an abstract `Priority` atom into its native priority
  value (string for SABnzbd, integer for NZBGet, etc.) via the
  `priority_profile` map on `Mydia.Settings.DownloadClientConfig`. When the
  profile is empty, adapters fall back to a hardcoded default mapping that
  preserves pre-wave-2 behaviour.

  ## Tiers

    * `:verylow` — lowest priority (e.g. archive, low-bandwidth window)
    * `:low` — below normal
    * `:normal` — default; what callers get when they don't specify
    * `:high` — above normal (e.g. user-initiated, high-quality release)
    * `:veryhigh` — highest priority (e.g. emergency reprocess)

  ## Usage

      iex> Mydia.Downloads.Priority.default()
      :normal

      iex> Mydia.Downloads.Priority.all()
      [:verylow, :low, :normal, :high, :veryhigh]

      iex> Mydia.Downloads.Priority.valid?(:high)
      true

      iex> Mydia.Downloads.Priority.valid?(:turbo)
      false
  """

  @type t :: :verylow | :low | :normal | :high | :veryhigh

  @all [:verylow, :low, :normal, :high, :veryhigh]

  @doc """
  Returns the full list of priority atoms, ordered from lowest to highest.
  """
  @spec all() :: [t()]
  def all, do: @all

  @doc """
  Returns the default priority atom (`:normal`).
  """
  @spec default() :: t()
  def default, do: :normal

  @doc """
  Returns `true` when the given value is one of the recognised priority atoms.
  """
  @spec valid?(any()) :: boolean()
  def valid?(value) when value in @all, do: true
  def valid?(_value), do: false

  @doc """
  Resolves an abstract priority atom to its client-native value via the
  given profile map, falling back to `default` when the profile does not
  contain an override for that atom.

  The profile is expected to be a `map()` keyed by string (`"verylow"`,
  `"low"`, `"normal"`, `"high"`, `"veryhigh"`); values are returned as-is
  so each adapter can interpret them in its own value domain.

  ## Examples

      iex> Mydia.Downloads.Priority.resolve(:high, %{}, "1")
      "1"

      iex> Mydia.Downloads.Priority.resolve(:high, %{"high" => "2"}, "1")
      "2"

      iex> Mydia.Downloads.Priority.resolve(nil, %{}, "0")
      "0"
  """
  @spec resolve(t() | nil, map(), term()) :: term()
  def resolve(nil, _profile, default), do: default

  def resolve(atom, profile, default) when atom in @all and is_map(profile) do
    case Map.fetch(profile, Atom.to_string(atom)) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def resolve(_atom, _profile, default), do: default
end
