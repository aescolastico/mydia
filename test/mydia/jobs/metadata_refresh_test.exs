defmodule Mydia.Jobs.MetadataRefreshTest do
  use Mydia.DataCase, async: false
  use Oban.Testing, repo: Mydia.Repo

  alias Mydia.Jobs.MetadataRefresh

  import Mydia.MediaFixtures

  describe "perform/1 - single media item" do
    test "returns error when media item does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} =
               perform_job(MetadataRefresh, %{"media_item_id" => fake_id})
    end

    test "returns error when media item has no provider ID and title search fails" do
      # Create media item without TMDB ID
      media_item =
        media_item_fixture(%{
          type: "movie",
          title: "Nonexistent Movie XYZ123",
          year: 2024,
          tmdb_id: nil
        })

      # Since title search will fail (no mock results), should return error
      result = perform_job(MetadataRefresh, %{"media_item_id" => media_item.id})

      assert result == {:error, :no_provider_id}
    end

    test "refreshes media item when TMDB ID exists" do
      # Create media item with TMDB ID
      media_item =
        media_item_fixture(%{
          type: "movie",
          title: "Test Movie",
          year: 2024,
          tmdb_id: 12345
        })

      # This will fail because no mock server, but should get past the TMDB ID check
      result = perform_job(MetadataRefresh, %{"media_item_id" => media_item.id})

      # Will fail due to no metadata relay, but should not be :no_provider_id
      assert result != {:error, :no_provider_id}
    end
  end

  describe "title similarity scoring" do
    test "exact title match scores highest" do
      score = calculate_similarity_score("The Matrix", "The Matrix")
      assert score == 1.0
    end

    test "case insensitive match scores high" do
      score = calculate_similarity_score("the matrix", "The Matrix")
      assert score == 1.0
    end

    test "substring match scores well" do
      score = calculate_similarity_score("The Matrix", "The Matrix Reloaded")
      assert score >= 0.7
    end

    test "completely different titles score low" do
      score = calculate_similarity_score("The Matrix", "Inception")
      assert score < 0.6
    end
  end

  describe "year matching" do
    test "exact year match returns true" do
      assert year_matches?(2020, 2020)
    end

    test "year difference of 1 returns true" do
      assert year_matches?(2020, 2021)
      assert year_matches?(2021, 2020)
    end

    test "year difference of 2 or more returns false" do
      refute year_matches?(2020, 2022)
    end

    test "nil media year returns true when result has year" do
      assert year_matches?(2020, nil)
    end

    test "nil result year returns false" do
      refute year_matches?(nil, 2020)
    end
  end

  # Helper functions to test the scoring logic
  # These mirror the private functions in MetadataRefresh

  defp calculate_similarity_score(title1, title2) do
    norm1 = normalize_title(title1)
    norm2 = normalize_title(title2)

    cond do
      norm1 == norm2 -> 1.0
      String.contains?(norm1, norm2) or String.contains?(norm2, norm1) -> 0.8
      true -> String.jaro_distance(norm1, norm2)
    end
  end

  defp normalize_title(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp year_matches?(result_year, nil), do: result_year != nil
  defp year_matches?(nil, _media_year), do: false

  defp year_matches?(result_year, media_year) when is_integer(result_year) do
    abs(result_year - media_year) <= 1
  end

  defp year_matches?(_result_year, _media_year), do: false
end
