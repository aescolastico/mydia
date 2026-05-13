defmodule Mydia.Library.ReleaseParser.TitleAssembler do
  @moduledoc """
  Reconstructs a human-readable title from the leftover title-zone
  tokens.

  The resolver has already marked which tokens belong to the title
  (everything classified as `:title_candidate` whose byte offset sits
  before the title boundary). This module just stitches them back into
  a single string, normalizes whitespace, and applies smart
  capitalization.

  ## Smart capitalization

  - Tokens that already contain at least one uppercase letter are kept
    as-is. This preserves intentional casing such as `iPhone`, `S01E01`,
    or branded `WALL-E` style titles.
  - Tokens that are entirely lowercase or entirely digits are
    title-cased: first byte uppercased, rest lowercased.
  - Tokens are joined with a single space.

  ## Byte-safety

  Per the parser-wide rule, **no `String.slice/3` and no
  `String.length/1`** anywhere in this module. We work on bytes via
  `:binary.part/3` and `binary_part/3`.
  """

  alias Mydia.Library.ReleaseParser.Token

  @doc """
  Build a title from the given tokens.

  `title_boundary` is the byte offset returned by
  `Tokenizer.title_boundary/2`. Tokens whose byte offset is greater than
  or equal to the boundary are dropped — they belong to the metadata
  zone even if a stray `:title_candidate` slipped through.

  Returns `nil` when no usable token remains. Returns a non-empty
  `String.t()` otherwise.
  """
  @spec assemble([Token.t()], non_neg_integer() | :infinity) :: String.t() | nil
  def assemble(tokens, title_boundary) when is_list(tokens) do
    tokens
    |> Enum.filter(&within_title_zone?(&1, title_boundary))
    |> Enum.map(& &1.value)
    |> Enum.map(&strip_outer_punct/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&smart_capitalize/1)
    |> Enum.join(" ")
    |> nil_if_empty()
  end

  defp within_title_zone?(%Token{byte_offset: o}, :infinity), do: o >= 0
  defp within_title_zone?(%Token{byte_offset: o}, boundary), do: o < boundary

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  # Strip leading/trailing punctuation bytes (ASCII). This handles cases
  # like a leftover `-` between sub-tokens. We only touch ASCII
  # punctuation to keep multibyte titles untouched.
  defp strip_outer_punct(value) when is_binary(value) do
    value
    |> strip_leading_punct()
    |> strip_trailing_punct()
  end

  defp strip_leading_punct(<<byte, rest::binary>>) when byte in ~c"-_.,:;!?'\"" do
    strip_leading_punct(rest)
  end

  defp strip_leading_punct(other), do: other

  defp strip_trailing_punct(<<>>), do: <<>>

  defp strip_trailing_punct(bin) when is_binary(bin) do
    size = byte_size(bin)
    last = :binary.at(bin, size - 1)

    if last in ~c"-_.,:;!?'\"" do
      strip_trailing_punct(binary_part(bin, 0, size - 1))
    else
      bin
    end
  end

  # Capitalize a single token using byte slicing only.
  defp smart_capitalize(""), do: ""

  defp smart_capitalize(value) do
    cond do
      has_upper?(value) -> value
      all_digits?(value) -> value
      true -> title_case_byte(value)
    end
  end

  defp has_upper?(value) do
    has_upper_bytes?(value, 0, byte_size(value))
  end

  defp has_upper_bytes?(_value, idx, size) when idx >= size, do: false

  defp has_upper_bytes?(value, idx, size) do
    byte = :binary.at(value, idx)

    if byte in ?A..?Z do
      true
    else
      has_upper_bytes?(value, idx + 1, size)
    end
  end

  defp all_digits?(value) do
    all_digits_bytes?(value, 0, byte_size(value))
  end

  defp all_digits_bytes?(_value, idx, size) when idx >= size, do: true

  defp all_digits_bytes?(value, idx, size) do
    byte = :binary.at(value, idx)

    if byte in ?0..?9 do
      all_digits_bytes?(value, idx + 1, size)
    else
      false
    end
  end

  # Title-case via byte slicing. The first byte is an ASCII letter (we
  # only get here when `has_upper?/1` returned false and `all_digits?/1`
  # returned false). For multibyte leading characters we keep the input
  # as-is, because byte-level uppercasing would corrupt them.
  defp title_case_byte(<<first, rest::binary>>) when first in ?a..?z do
    upper_first = first - 32
    <<upper_first, String.downcase(rest)::binary>>
  end

  defp title_case_byte(value), do: value
end
