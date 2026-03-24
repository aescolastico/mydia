defmodule Mydia.Settings.DownloadClientConfig do
  @moduledoc """
  Schema for download client configurations (qBittorrent, Transmission, rTorrent, Blackhole, HTTP).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: binary(),
          name: String.t() | nil,
          type: atom() | nil,
          enabled: boolean(),
          priority: integer(),
          host: String.t() | nil,
          port: integer() | nil,
          use_ssl: boolean(),
          url_base: String.t() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          api_key: String.t() | nil,
          category: String.t() | nil,
          download_directory: String.t() | nil,
          connection_settings: map() | nil,
          remove_completed: boolean(),
          updated_by: Mydia.Accounts.User.t() | nil | Ecto.Association.NotLoaded.t(),
          updated_by_id: binary() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @client_types [:qbittorrent, :transmission, :rtorrent, :blackhole, :http, :sabnzbd, :nzbget]

  schema "download_client_configs" do
    field :name, :string
    field :type, Ecto.Enum, values: @client_types
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 1
    field :host, :string
    field :port, :integer
    field :use_ssl, :boolean, default: false
    field :url_base, :string
    field :username, :string
    field :password, :string
    field :api_key, :string
    field :category, :string
    field :download_directory, :string
    field :connection_settings, Mydia.Settings.JsonMapType
    field :remove_completed, :boolean, default: false

    belongs_to :updated_by, Mydia.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating a download client config.
  """
  def changeset(download_client_config, attrs) do
    download_client_config
    |> cast(attrs, [
      :name,
      :type,
      :enabled,
      :priority,
      :host,
      :port,
      :use_ssl,
      :url_base,
      :username,
      :password,
      :api_key,
      :category,
      :download_directory,
      :connection_settings,
      :remove_completed,
      :updated_by_id
    ])
    |> validate_required([:name, :type])
    |> validate_inclusion(:type, @client_types)
    |> validate_by_type()
    |> validate_number(:priority, greater_than: 0)
    |> unique_constraint(:name)
  end

  # Blackhole clients use filesystem paths instead of network config
  defp validate_by_type(changeset) do
    case get_field(changeset, :type) do
      :blackhole ->
        changeset
        |> validate_blackhole_config()

      _network_client ->
        changeset
        |> validate_required([:host, :port])
        |> validate_number(:port, greater_than: 0, less_than: 65536)
    end
  end

  defp validate_blackhole_config(changeset) do
    case get_field(changeset, :connection_settings) do
      %{"watch_folder" => watch, "completed_folder" => completed}
      when is_binary(watch) and is_binary(completed) and watch != "" and completed != "" ->
        changeset

      _ ->
        changeset
        |> add_error(:connection_settings, "must include watch_folder and completed_folder")
    end
  end
end
