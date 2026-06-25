defmodule Mydia.Library.NamingTemplate do
  @moduledoc """
  Renders file and folder names from admin-configured templates.

  ## Template language

  A *token* is written `{{token_name}}` where `token_name` matches
  `[a-z][a-z0-9_]*`. Everything else, **including a single `{` or `}`**, is a
  literal character. Only the exact `{{name}}` shape is substituted.

  Because only `{{identifier}}` is a token, brace-wrapping a token works
  naturally:

      iex> NamingTemplate.render("{{title}} ({{year}}) {tmdb-{{tmdb}}}", %{
      ...>   "title" => "The Office", "year" => "2005", "tmdb" => "2316"
      ...> })
      "The Office (2005) {tmdb-2316}"

  In `{tmdb-{{tmdb}}}` the provider tag style (`tmdb-`) is literal text chosen
  by the user, while `{{tmdb}}` injects only the stored provider ID.

  ## Render post-processing

  After substitution the result is cleaned up, in order:

  1. Empty provider ID tags such as `{tmdb-}` or `[tvdbid-]` are removed.
  2. Empty literal `{}` and `()` pairs are removed. This handles a missing
     provider id inside `{tmdb-{{tmdb}}}` and a missing year inside `({{year}})`.
     (Real titles never contain *empty* brace/paren pairs, so this is safe.)
  3. Runs of whitespace are squeezed to a single space.
  4. Dangling separators left by an empty token (a leading/trailing or doubled
     `-`) are trimmed.
  5. Leading/trailing whitespace is trimmed.

  Callers are responsible for appending the file extension and for sanitizing
  illegal filename characters (see `Mydia.Library.FileNamer.sanitize_title/1`).
  """

  # Token names are identifiers; the surrounding `{{ }}` may contain padding
  # whitespace (e.g. `{{ title }}`). Single braces never match.
  @token_re ~r/\{\{\s*([a-z][a-z0-9_]*)\s*\}\}/

  @typedoc "A map of token name (string) to its already-rendered string value."
  @type context :: %{optional(String.t()) => term()}

  # The full catalog of token names recognized by the naming UI. Not every
  # token is meaningful in every template (e.g. `sxxeyy` only applies to
  # episodes), but any of these is accepted by validation.
  @tokens ~w(
    title year season episode sxxeyy episode_title
    quality audio hdr codec release_group
    tmdb tvdb imdb
  )

  @doc "Returns every token name the naming system understands."
  @spec tokens() :: [String.t()]
  def tokens, do: @tokens

  @doc """
  Returns the list of token names recognized in `template`.

  Useful for validation and for surfacing which tokens an admin used.

      iex> NamingTemplate.tokens_in("{{title}} ({{year}})")
      ["title", "year"]
  """
  @spec tokens_in(String.t()) :: [String.t()]
  def tokens_in(template) when is_binary(template) do
    @token_re
    |> Regex.scan(template, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> Enum.uniq()
  end

  @doc """
  Validates a template against a set of allowed token names.

  Returns `:ok`, or `{:error, unknown_tokens}` listing any tokens that are not
  in `allowed`.

      iex> NamingTemplate.validate("{{title}} {{bogus}}", ["title", "year"])
      {:error, ["bogus"]}

      iex> NamingTemplate.validate("{{title}} ({{year}})", ["title", "year"])
      :ok
  """
  @spec validate(String.t(), [String.t()]) :: :ok | {:error, [String.t()]}
  def validate(template, allowed) when is_binary(template) and is_list(allowed) do
    case Enum.reject(tokens_in(template), &(&1 in allowed)) do
      [] -> :ok
      unknown -> {:error, unknown}
    end
  end

  @doc """
  Renders `template`, substituting `{{token}}` occurrences from `context`.

  Tokens missing from `context` (or whose value is `nil`/`""`) render as an
  empty string. Non-string values are converted with `to_string/1`.
  """
  @spec render(String.t(), context()) :: String.t()
  def render(template, context) when is_binary(template) and is_map(context) do
    template
    |> substitute(context)
    |> collapse_empty_provider_tags()
    |> collapse_empty_pairs()
    |> squeeze_whitespace()
    |> trim_separators()
  end

  defp substitute(template, context) do
    Regex.replace(@token_re, template, fn _full, name ->
      context
      |> Map.get(name)
      |> value_to_string()
    end)
  end

  defp value_to_string(nil), do: ""
  defp value_to_string(value) when is_binary(value), do: value
  defp value_to_string(value), do: to_string(value)

  defp collapse_empty_provider_tags(string) do
    String.replace(string, ~r/[\{\[]\s*(?:tmdbid|tmdb|tvdbid|tvdb|imdbid|imdb)-\s*[\}\]]/i, "")
  end

  defp collapse_empty_pairs(string) do
    string
    |> String.replace(~r/\{\s*\}/, "")
    |> String.replace(~r/\(\s*\)/, "")
  end

  defp squeeze_whitespace(string) do
    String.replace(string, ~r/[ \t]+/, " ")
  end

  # Remove dangling separators left behind by an empty token, e.g.
  # `Show -  - [tag]` (empty episode title) → `Show - [tag]`, and trim
  # leading/trailing separators and whitespace.
  defp trim_separators(string) do
    string
    |> String.replace(~r/\s+-\s+-\s+/, " - ")
    |> String.replace(~r/^[\s\-]+/, "")
    |> String.replace(~r/[\s\-]+$/, "")
    |> String.trim()
  end
end
