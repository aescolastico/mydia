defmodule Mydia.Library.ReleaseParser.TitleAssemblerTest do
  use ExUnit.Case, async: true

  alias Mydia.Library.ReleaseParser.TitleAssembler
  alias Mydia.Library.ReleaseParser.Token

  defp token(value, offset) do
    %Token{value: value, byte_offset: offset, byte_length: byte_size(value)}
  end

  describe "assemble/2" do
    test "joins multiple tokens with single spaces" do
      tokens = [token("Show", 0), token("Name", 5)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Show Name"
    end

    test "lowercase tokens become title case" do
      tokens = [token("show", 0), token("name", 5)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Show Name"
    end

    test "normalizes mixed-case tokens to title-case (matches V2 smart_capitalize)" do
      # V2's smart_capitalize/1 normalizes `iPhone` to `Iphone` via
      # `String.capitalize/1` and we preserve V2's behavior for parity.
      tokens = [token("iPhone", 0), token("App", 7)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Iphone App"
    end

    test "drops tokens past the title boundary" do
      tokens = [token("Show", 0), token("Name", 5), token("S01E01", 10)]
      assert TitleAssembler.assemble(tokens, 10) == "Show Name"
    end

    test "returns nil when no tokens are within the boundary" do
      tokens = [token("S01E01", 0)]
      assert TitleAssembler.assemble(tokens, 0) == nil
    end

    test "returns nil for empty token list" do
      assert TitleAssembler.assemble([], :infinity) == nil
    end

    test "strips leading and trailing ASCII punctuation" do
      tokens = [token("-show-", 0), token(".name.", 7)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Show Name"
    end

    test "preserves multibyte token values" do
      tokens = [token("葬送のフリーレン", 0)]
      assert TitleAssembler.assemble(tokens, :infinity) == "葬送のフリーレン"
    end

    test "digit-only tokens stay as digits" do
      tokens = [token("Black", 0), token("Phone", 6), token("2", 12)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Black Phone 2"
    end

    test "single token at byte_offset 0 still in title zone with :infinity" do
      tokens = [token("Single", 0)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Single"
    end

    test "all-uppercase words are title-cased (matches V2)" do
      # V2's smart_capitalize/1 lowers all-upper to title-case via
      # `String.capitalize/1`. We preserve V2's behavior for parity.
      tokens = [token("MOVIE", 0)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Movie"
    end

    test "fully lowercase word with no upper is title-cased" do
      tokens = [token("madame", 0), token("web", 7)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Madame Web"
    end

    test "punctuation-only token is dropped" do
      tokens = [token("-", 0), token("show", 2)]
      assert TitleAssembler.assemble(tokens, :infinity) == "Show"
    end
  end
end
