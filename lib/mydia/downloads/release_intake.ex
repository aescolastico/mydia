defmodule Mydia.Downloads.ReleaseIntake do
  @moduledoc """
  The sole release-name parse entry point for the Downloads context.

  Composes `Mydia.Downloads.ReleaseValidator` ahead of
  `Mydia.Library.ReleaseParser` so the validation gate (fake / malicious /
  hashed / password / yenc / reversed / executable-extension releases) is never
  bypassed before a release name reaches the matcher.

  `ReleaseParser` itself never rejects input — it always returns a
  `%ParsedFileInfo{}`, sometimes typed `:unknown`. This module converts that
  always-a-struct shape back into the reject-or-parse contract the download
  callers depend on:

  - validator rejection → `{:error, reason}` (the validator's specific reason)
  - `:unknown` type with no usable title → `{:error, :unable_to_parse}`
  - `:unknown` type with a usable title → `{:ok, info}` so the matcher's
    title-similarity path can still produce a *suggestion*
  - otherwise → `{:ok, %ParsedFileInfo{}}`

  Downloads callers must use this function rather than calling
  `Library.ReleaseParser` directly for the initial parse. The one exception is
  `Mydia.Indexers.ReleaseRanker`, which already runs the validator over its
  result list separately and parses titles directly afterward.
  """

  alias Mydia.Downloads.ReleaseValidator
  alias Mydia.Library.ReleaseParser
  alias Mydia.Library.Structs.ParsedFileInfo

  @doc """
  Validate then parse a release name.

  Returns `{:ok, %ParsedFileInfo{}}` for a usable parse, or `{:error, reason}`
  when the validator rejects the name or the parser cannot extract anything
  usable. See the module doc for the full contract.
  """
  @spec parse_release(String.t()) :: {:ok, ParsedFileInfo.t()} | {:error, atom()}
  def parse_release(name) when is_binary(name) do
    with {:ok, validated} <- ReleaseValidator.validate_release(name) do
      validated
      |> ReleaseParser.parse()
      |> classify_parse_result()
    end
  end

  defp classify_parse_result(%ParsedFileInfo{type: :unknown} = info) do
    if usable_title?(info.title) do
      {:ok, info}
    else
      {:error, :unable_to_parse}
    end
  end

  defp classify_parse_result(%ParsedFileInfo{} = info), do: {:ok, info}

  defp usable_title?(title) when is_binary(title), do: String.trim(title) != ""
  defp usable_title?(_), do: false
end
