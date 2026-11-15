defmodule Mydia.Settings.Naming do
  @moduledoc """
  Validates and saves the file naming settings as one operation.

  These settings live in the existing `config_settings` table. The runtime
  configuration is reloaded after a successful transaction so imports and
  rename previews use the new templates immediately.
  """

  alias Mydia.Config.Loader
  alias Mydia.Config.Schema
  alias Mydia.Library.NamingTemplate
  alias Mydia.Repo
  alias Mydia.Settings

  @template_fields [:movie_folder, :tv_folder, :season_folder, :movie_file, :episode_file]
  @fields [:season_folders | @template_fields]
  @env_variables ~w(
    NAMING_SEASON_FOLDERS NAMING_SEASON_FOLDER NAMING_MOVIE_FOLDER
    NAMING_TV_FOLDER NAMING_MOVIE_FILE NAMING_EPISODE_FILE
  )

  @doc "Naming environment variables that currently override saved values."
  def env_overrides do
    Enum.filter(@env_variables, &(System.get_env(&1) not in [nil, ""]))
  end

  @doc "Form params for the active configuration."
  def params(%Schema.Naming{} = naming) do
    Map.new(@fields, fn field -> {to_string(field), to_string(Map.fetch!(naming, field))} end)
  end

  @doc "Validates all templates, returning a map of field names to messages."
  def validate(params) when is_map(params) do
    Enum.reduce(@template_fields, %{}, fn field, errors ->
      value = Map.get(params, to_string(field)) || ""

      result =
        if is_binary(value),
          do: NamingTemplate.validate_for(value, field),
          else: {:error, "must be text"}

      case result do
        :ok -> errors
        {:error, reason} -> Map.put(errors, to_string(field), reason)
      end
    end)
  end

  @doc "Saves all settings atomically, then refreshes the active configuration."
  def save(params, user_id) when is_map(params) do
    case validate(params) do
      errors when map_size(errors) > 0 ->
        {:error, {:validation, errors}}

      _ ->
        params = Map.put(params, "season_folders", to_string(enabled?(params)))

        case Repo.transaction(fn -> persist!(params, user_id) end) do
          {:ok, _} -> Loader.reload()
          {:error, reason} -> {:error, {:persist, reason}}
        end
    end
  end

  defp persist!(params, user_id) do
    Enum.each(@fields, fn field ->
      key = "naming.#{field}"

      case Settings.upsert_config_setting(%{
             key: key,
             value: Map.fetch!(params, to_string(field)),
             category: :naming,
             updated_by_id: user_id
           }) do
        {:ok, _setting} -> :ok
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp enabled?(params), do: params["season_folders"] in [true, "true", "on", "1"]
end
