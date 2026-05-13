# Mock Bitmagnet fixture — used when --mock-response is passed.

%{
  source: "bitmagnet-mock",
  sampled_at: "2026-05-13T15:26:47.568488Z",
  cases: [
    %{
      input: "Mock.Show.S01E01.1080p.WEB-DL.x265-MOCK",
      soft_truth: %{title: "Mock Show", content_type: "tv_show", video_resolution: "1080p"},
      info_hash: "0000000000000000000000000000000000000001"
    },
    %{
      input: "Mock.Movie.2024.2160p.BluRay.x265-MOCK",
      soft_truth: %{title: "Mock Movie", content_type: "movie", video_resolution: "2160p"},
      info_hash: "0000000000000000000000000000000000000002"
    }
  ]
}
