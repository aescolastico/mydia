defmodule Mix.Tasks.Mydia.Parser.Harvest do
  @moduledoc """
  Harvests release-parser regression corpora from upstream sources.

  Runs two underlying scripts:
    - `scripts/harvest_sonarr_fixtures.exs` — Sonarr + Radarr ParserTests
    - `scripts/sample_bitmagnet_corpus.exs` — local Bitmagnet GraphQL sample

  ## Usage

      mix mydia.parser.harvest
      mix mydia.parser.harvest --target test/fixtures/release_parser
      mix mydia.parser.harvest --skip-bitmagnet
      mix mydia.parser.harvest --skip-sonarr --bitmagnet-endpoint http://localhost:3333/graphql

  ## Options

    * `--target PATH` — output directory (default: `test/fixtures/release_parser`)
    * `--skip-sonarr` — skip Sonarr ParserTests harvest
    * `--skip-radarr` — skip Radarr ParserTests harvest
    * `--skip-bitmagnet` — skip Bitmagnet sampling
    * `--bitmagnet-endpoint URL` — Bitmagnet GraphQL endpoint (default: http://localhost:3333/graphql)
    * `--bitmagnet-limit N` — TV + movie samples to pull (default: 2000 each)
    * `--bitmagnet-mock` — generate a tiny mock fixture instead of hitting Bitmagnet (CI determinism)

  Bitmagnet sampling is best-effort. If Bitmagnet is unreachable, an empty
  fixture file is written and the harvest continues.
  """

  use Mix.Task

  @shortdoc "Harvest Sonarr/Radarr/Bitmagnet release-parser regression corpora"

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          target: :string,
          skip_sonarr: :boolean,
          skip_radarr: :boolean,
          skip_bitmagnet: :boolean,
          bitmagnet_endpoint: :string,
          bitmagnet_limit: :integer,
          bitmagnet_mock: :boolean
        ]
      )

    target = opts[:target] || "test/fixtures/release_parser"

    unless opts[:skip_sonarr] and opts[:skip_radarr] do
      sonarr_args =
        ["--target", target]
        |> maybe_add(opts[:skip_sonarr], "--skip-sonarr")
        |> maybe_add(opts[:skip_radarr], "--skip-radarr")

      Mix.shell().info("\nHarvesting Sonarr/Radarr ParserTests...")
      Mix.Task.run("run", ["scripts/harvest_sonarr_fixtures.exs"] ++ sonarr_args)
    end

    unless opts[:skip_bitmagnet] do
      bitmagnet_args =
        ["--target", target]
        |> maybe_add(opts[:bitmagnet_endpoint], "--endpoint", opts[:bitmagnet_endpoint])
        |> maybe_add_int(opts[:bitmagnet_limit], "--limit")
        |> maybe_add(opts[:bitmagnet_mock], "--mock-response")

      Mix.shell().info("\nSampling Bitmagnet...")
      Mix.Task.run("run", ["scripts/sample_bitmagnet_corpus.exs"] ++ bitmagnet_args)
    end

    Mix.shell().info("\nHarvest complete. Corpus files are in #{target}.")
  end

  defp maybe_add(args, true, flag), do: args ++ [flag]
  defp maybe_add(args, _, _flag), do: args

  defp maybe_add(args, nil, _flag, _value), do: args
  defp maybe_add(args, false, _flag, _value), do: args
  defp maybe_add(args, _, flag, value), do: args ++ [flag, value]

  defp maybe_add_int(args, nil, _flag), do: args
  defp maybe_add_int(args, value, flag), do: args ++ [flag, to_string(value)]
end
