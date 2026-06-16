defmodule Mydia.Downloads.QueueMatchSuggestionsTest do
  @moduledoc """
  U5: queue.refresh_match_suggestions/1 routes through ReleaseIntake
  (validate + parse) and the reworked matcher, preserving empty-on-failure.
  """
  use Mydia.DataCase, async: true

  alias Mydia.Downloads.Queue

  import Mydia.Factory
  import Mydia.DownloadsFixtures

  defp suggestions(download) do
    {:ok, updated} = Queue.refresh_match_suggestions(download)
    updated.metadata["match_suggestions"] || updated.metadata[:match_suggestions] || []
  end

  test "a valid title yields suggestions from the matcher" do
    insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})
    download = download_fixture(%{title: "The.Matrix.1999.1080p.BluRay.x264-GROUP"})

    assert Enum.any?(suggestions(download), fn s ->
             (s["title"] || s[:title]) == "The Matrix"
           end)
  end

  test "a malicious title is rejected by the validator and yields no suggestions" do
    # Same title as above but with a malware extension — the validation gate in
    # ReleaseIntake rejects it before matching, so no suggestions are produced.
    insert(:media_item, %{type: "movie", title: "The Matrix", year: 1999, monitored: true})
    download = download_fixture(%{title: "The.Matrix.1999.1080p.BluRay.x264-GROUP.exe"})

    assert suggestions(download) == []
  end
end
