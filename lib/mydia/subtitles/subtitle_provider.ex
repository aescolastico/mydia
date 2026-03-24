defmodule Mydia.Subtitles.SubtitleProvider do
  @moduledoc """
  Schema for subtitle provider configurations.

  Manages multiple subtitle sources per user, including:
  - Relay providers (unlimited, no credentials)
  - OpenSubtitles providers (200/day free, 1000/day VIP)

  Similar to download client configs, users can configure multiple providers
  with priorities for automatic selection and fallback.

  ## Provider Types

  ### Relay Provider
  - Type: `:relay`
  - No credentials required
  - Unlimited quota
  - Routes through metadata-relay service

  ### OpenSubtitles Provider
  - Type: `:opensubtitles`
  - Requires username and password (or API key)
  - Quota tracked (200/day free, 1000/day VIP)
  - Direct API connection

  ## Examples

      # Relay provider
      %SubtitleProvider{
        user_id: "user-uuid",
        name: "Default Relay",
        type: :relay,
        enabled: true,
        priority: 0
      }

      # OpenSubtitles free account
      %SubtitleProvider{
        user_id: "user-uuid",
        name: "My OpenSubtitles",
        type: :opensubtitles,
        username: "user@example.com",
        password: "password123",
        enabled: true,
        priority: 1,
        quota_remaining: 142,
        quota_total: 200,
        vip_status: false
      }

  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @provider_types [:relay, :opensubtitles]

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          type: atom() | nil,
          enabled: boolean(),
          priority: integer(),
          username: String.t() | nil,
          password: String.t() | nil,
          api_key: String.t() | nil,
          quota_remaining: integer() | nil,
          quota_total: integer() | nil,
          quota_reset_at: DateTime.t() | nil,
          vip_status: boolean(),
          user: Mydia.Accounts.User.t() | Ecto.Association.NotLoaded.t(),
          user_id: binary() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "subtitle_providers" do
    field :name, :string
    field :type, Ecto.Enum, values: @provider_types
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 0

    # OpenSubtitles-specific fields
    field :username, :string
    field :password, :string
    field :api_key, :string

    # Quota tracking
    field :quota_remaining, :integer
    field :quota_total, :integer
    field :quota_reset_at, :utc_datetime
    field :vip_status, :boolean, default: false

    belongs_to :user, Mydia.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a subtitle provider.

  ## Validations

  - `name` is required and must be unique per user
  - `type` must be one of: `:relay`, `:opensubtitles`
  - `priority` must be >= 0 (higher values = higher priority)
  - Relay providers must not have credentials
  - OpenSubtitles providers must have username and password (or API key)

  ## Examples

      # Create relay provider
      iex> changeset(%SubtitleProvider{}, %{
      ...>   user_id: "user-uuid",
      ...>   name: "Default Relay",
      ...>   type: :relay
      ...> })

      # Create OpenSubtitles provider
      iex> changeset(%SubtitleProvider{}, %{
      ...>   user_id: "user-uuid",
      ...>   name: "My OpenSubtitles",
      ...>   type: :opensubtitles,
      ...>   username: "user@example.com",
      ...>   password: "password123"
      ...> })

  """
  def changeset(subtitle_provider, attrs) do
    subtitle_provider
    |> cast(attrs, [
      :user_id,
      :name,
      :type,
      :enabled,
      :priority,
      :username,
      :password,
      :api_key,
      :quota_remaining,
      :quota_total,
      :quota_reset_at,
      :vip_status
    ])
    |> validate_required([:user_id, :name, :type])
    |> validate_inclusion(:type, @provider_types)
    |> validate_number(:priority, greater_than_or_equal_to: 0)
    |> unique_constraint([:user_id, :name], name: :subtitle_providers_user_id_name_index)
    |> validate_credentials()
  end

  # Validate credentials based on provider type
  defp validate_credentials(changeset) do
    type = get_field(changeset, :type)

    case type do
      :relay ->
        # Relay providers should not have credentials
        changeset
        |> validate_empty(:username, "must not be set for relay providers")
        |> validate_empty(:password, "must not be set for relay providers")
        |> validate_empty(:api_key, "must not be set for relay providers")

      :opensubtitles ->
        # OpenSubtitles providers require either username+password or API key
        username = get_field(changeset, :username)
        password = get_field(changeset, :password)
        api_key = get_field(changeset, :api_key)

        cond do
          # Has API key - valid
          api_key && api_key != "" ->
            changeset

          # Has username and password - valid
          username && username != "" && password && password != "" ->
            changeset

          # Missing credentials - invalid
          true ->
            changeset
            |> add_error(
              :username,
              "must provide either username+password or api_key for OpenSubtitles providers"
            )
        end

      _ ->
        changeset
    end
  end

  # Helper to validate a field is empty/nil
  defp validate_empty(changeset, field, message) do
    value = get_field(changeset, field)

    if value && value != "" do
      add_error(changeset, field, message)
    else
      changeset
    end
  end

  @doc """
  Quota update changeset for tracking OpenSubtitles usage.

  Updates quota fields without requiring full validation.

  ## Examples

      iex> quota_changeset(provider, %{
      ...>   quota_remaining: 199,
      ...>   quota_total: 200,
      ...>   quota_reset_at: ~U[2024-01-01 00:00:00Z]
      ...> })

  """
  def quota_changeset(subtitle_provider, attrs) do
    subtitle_provider
    |> cast(attrs, [:quota_remaining, :quota_total, :quota_reset_at, :vip_status])
    |> validate_number(:quota_remaining, greater_than_or_equal_to: 0)
    |> validate_number(:quota_total, greater_than: 0)
  end

  @doc """
  Returns true if the provider's quota is exhausted.

  Relay providers always return false (unlimited quota).

  ## Examples

      iex> quota_exhausted?(%SubtitleProvider{type: :relay})
      false

      iex> quota_exhausted?(%SubtitleProvider{type: :opensubtitles, quota_remaining: 0})
      true

      iex> quota_exhausted?(%SubtitleProvider{type: :opensubtitles, quota_remaining: 10})
      false

  """
  def quota_exhausted?(%__MODULE__{type: :relay}), do: false
  def quota_exhausted?(%__MODULE__{quota_remaining: nil}), do: false
  def quota_exhausted?(%__MODULE__{quota_remaining: 0}), do: true
  def quota_exhausted?(%__MODULE__{}), do: false

  @doc """
  Returns true if the provider's quota is running low (< 10%).

  Relay providers always return false (unlimited quota).

  ## Examples

      iex> quota_low?(%SubtitleProvider{type: :relay})
      false

      iex> quota_low?(%SubtitleProvider{quota_remaining: 5, quota_total: 200})
      true

      iex> quota_low?(%SubtitleProvider{quota_remaining: 50, quota_total: 200})
      false

  """
  def quota_low?(%__MODULE__{type: :relay}), do: false
  def quota_low?(%__MODULE__{quota_remaining: nil}), do: false
  def quota_low?(%__MODULE__{quota_total: nil}), do: false

  def quota_low?(%__MODULE__{quota_remaining: remaining, quota_total: total})
      when is_integer(remaining) and is_integer(total) and total > 0 do
    remaining / total < 0.1
  end

  def quota_low?(%__MODULE__{}), do: false
end
