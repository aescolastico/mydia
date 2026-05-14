defmodule Mydia.Downloads.ContentType do
  @moduledoc """
  Classifies the body returned from an indexer download URL.

  Indexer download endpoints can respond with a bencoded `.torrent` file,
  an NZB XML document, a `magnet:` URI as plain text, or an HTML page
  (typically when an aggregator site requires further navigation, or when
  authentication / Cloudflare interstitials kick in).

  Detection is structural rather than prefix-based so trackerless torrents
  (e.g. emitted by `anacrolix/torrent`, whose alphabetised keys start with
  `comment`/`created by` rather than `announce`) are recognised correctly.
  """

  alias Mydia.Downloads.TorrentHash

  @type detected :: :magnet | :torrent | :nzb | :unknown

  @doc """
  Classifies the binary as `:magnet`, `:torrent`, `:nzb`, or `:unknown`.
  """
  @spec detect(binary()) :: detected
  def detect(body) when is_binary(body) and byte_size(body) > 0 do
    cond do
      magnet?(body) -> :magnet
      TorrentHash.valid_metainfo?(body) -> :torrent
      nzb?(body) -> :nzb
      true -> :unknown
    end
  end

  def detect(_), do: :unknown

  defp magnet?(body), do: String.starts_with?(body, "magnet:")

  defp nzb?(body) do
    String.contains?(body, "<?xml") and String.contains?(body, "nzb")
  end
end
