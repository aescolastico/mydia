defmodule Mydia.Indexers.FlareSolverr do
  @moduledoc """
  Client for communicating with FlareSolverr API.

  FlareSolverr is a proxy server to bypass Cloudflare and DDoS-GUARD protection.
  It uses a headless browser to solve JavaScript challenges and returns cookies
  that can be reused for subsequent requests.

  ## Configuration

  FlareSolverr is configured via application environment:

      config :mydia, :flaresolverr,
        enabled: true,
        url: "http://flaresolverr:8191",
        timeout: 60_000,
        max_timeout: 120_000

  ## Usage

      # Check if FlareSolverr is available
      if Mydia.Indexers.FlareSolverr.available?() do
        case Mydia.Indexers.FlareSolverr.get("https://protected-site.com") do
          {:ok, response} ->
            # Use response.solution.response (HTML body)
            # Use response.solution.cookies for subsequent requests
          {:error, reason} ->
            # Handle error
        end
      end

  ## FlareSolverr API

  FlareSolverr exposes a REST API at `/v1` that accepts POST requests with JSON body.
  Supported commands:
  - `request.get` - Fetch a URL and solve any challenges
  - `request.post` - POST to a URL and solve any challenges
  - `sessions.create` - Create a persistent browser session
  - `sessions.list` - List active sessions
  - `sessions.destroy` - Destroy a session
  """

  alias Mydia.Indexers.FlareSolverr.Response

  require Logger

  @api_path "/v1"

  @doc """
  Fetches a URL through FlareSolverr, solving any Cloudflare challenges.

  ## Options

    * `:timeout` - Request timeout in milliseconds (default: from config)
    * `:max_timeout` - Maximum timeout for challenging sites (default: from config)
    * `:session` - Optional session ID to reuse browser instance
    * `:cookies` - Optional list of cookies to include in the request
    * `:proxy` - Optional proxy URL to use

  ## Examples

      iex> FlareSolverr.get("https://protected-site.com")
      {:ok, %Response{status: "ok", solution: %{...}}}

      iex> FlareSolverr.get("https://protected-site.com", timeout: 90_000)
      {:ok, %Response{status: "ok", solution: %{...}}}
  """
  @spec get(String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def get(url, opts \\ []) do
    with {:ok, config} <- get_config(),
         :ok <- validate_enabled(config) do
      execute_request("request.get", url, opts, config)
    end
  end

  @doc """
  Sends a POST request through FlareSolverr.

  ## Options

  Same as `get/2`, plus:
    * `:post_data` - Form data to POST (map or URL-encoded string)

  ## Examples

      iex> FlareSolverr.post("https://protected-site.com/login", post_data: %{user: "test"})
      {:ok, %Response{status: "ok", solution: %{...}}}
  """
  @spec post(String.t(), keyword()) :: {:ok, Response.t()} | {:error, term()}
  def post(url, opts \\ []) do
    with {:ok, config} <- get_config(),
         :ok <- validate_enabled(config) do
      execute_request("request.post", url, opts, config)
    end
  end

  @doc """
  Checks if FlareSolverr is configured and enabled.

  Returns `true` if FlareSolverr is enabled and has a URL configured.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    case get_config() do
      {:ok, config} -> config.enabled && is_binary(config.url) && config.url != ""
      {:error, _} -> false
    end
  end

  @doc """
  Checks if FlareSolverr service is available and responding.

  This performs a health check request to verify the service is running.
  """
  @spec available?() :: boolean()
  def available? do
    case health_check() do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Performs a health check on the FlareSolverr service.

  Returns service information if healthy.
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    with {:ok, config} <- get_config(),
         :ok <- validate_enabled(config) do
      url = "#{config.url}#{@api_path}"

      body = %{
        cmd: "sessions.list"
      }

      case Req.post(url, json: body, connect_timeout: 5_000, receive_timeout: 10_000) do
        {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
          {:ok,
           %{
             status: body["status"],
             version: body["version"],
             sessions: body["sessions"] || []
           }}

        {:ok, %Req.Response{status: status, body: body}} ->
          {:error, {:http_error, status, body}}

        {:error, %Mint.TransportError{reason: reason}} ->
          {:error, {:connection_error, reason}}

        {:error, reason} ->
          {:error, {:request_error, reason}}
      end
    end
  end

  @doc """
  Returns the current FlareSolverr configuration.
  """
  @spec config() :: map() | nil
  def config do
    case get_config() do
      {:ok, config} -> config
      {:error, _} -> nil
    end
  end

  ## Private Functions

  defp get_config do
    case Application.get_env(:mydia, :flaresolverr) do
      nil ->
        {:error, :not_configured}

      config when is_list(config) ->
        {:ok,
         %{
           enabled: Keyword.get(config, :enabled, false),
           url: Keyword.get(config, :url),
           timeout: Keyword.get(config, :timeout, 60_000),
           max_timeout: Keyword.get(config, :max_timeout, 120_000)
         }}

      config when is_map(config) ->
        {:ok,
         %{
           enabled: Map.get(config, :enabled, false),
           url: Map.get(config, :url),
           timeout: Map.get(config, :timeout, 60_000),
           max_timeout: Map.get(config, :max_timeout, 120_000)
         }}
    end
  end

  defp validate_enabled(%{enabled: true, url: url}) when is_binary(url) and url != "" do
    :ok
  end

  defp validate_enabled(%{enabled: false}) do
    {:error, :disabled}
  end

  defp validate_enabled(_) do
    {:error, :not_configured}
  end

  defp execute_request(cmd, url, opts, config) do
    flaresolverr_url = "#{config.url}#{@api_path}"
    timeout = opts[:timeout] || config.timeout
    max_timeout = opts[:max_timeout] || config.max_timeout

    body =
      %{
        cmd: cmd,
        url: url,
        maxTimeout: max_timeout
      }
      |> maybe_add_session(opts[:session])
      |> maybe_add_cookies(opts[:cookies])
      |> maybe_add_proxy(opts[:proxy])
      |> maybe_add_post_data(opts[:post_data])

    Logger.debug("FlareSolverr request: #{cmd} #{url}")

    case Req.post(flaresolverr_url, json: body, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: response_body}} when is_map(response_body) ->
        handle_response(response_body, url)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("FlareSolverr HTTP error #{status}: #{inspect(body)}")
        {:error, {:http_error, status, body}}

      {:error, %Mint.TransportError{reason: :timeout}} ->
        Logger.warning("FlareSolverr request timeout for #{url}")
        {:error, :timeout}

      {:error, %Mint.TransportError{reason: reason}} ->
        Logger.error("FlareSolverr connection error: #{inspect(reason)}")
        {:error, {:connection_error, reason}}

      {:error, reason} ->
        Logger.error("FlareSolverr request failed: #{inspect(reason)}")
        {:error, {:request_error, reason}}
    end
  end

  defp handle_response(%{"status" => "ok"} = body, url) do
    case Response.from_json(body) do
      {:ok, response} ->
        duration = Response.duration_ms(response)
        Logger.info("FlareSolverr solved challenge for #{url} in #{duration}ms")
        {:ok, response}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp handle_response(%{"status" => "error", "message" => message}, url) do
    Logger.warning("FlareSolverr failed for #{url}: #{message}")
    error_type = categorize_error(message)
    {:error, {error_type, message}}
  end

  defp handle_response(body, url) do
    Logger.error("FlareSolverr unexpected response for #{url}: #{inspect(body)}")
    {:error, {:unexpected_response, body}}
  end

  defp categorize_error(message) when is_binary(message) do
    message_lower = String.downcase(message)

    cond do
      String.contains?(message_lower, "timeout") -> :challenge_timeout
      String.contains?(message_lower, "challenge") -> :challenge_failed
      String.contains?(message_lower, "cloudflare") -> :cloudflare_error
      String.contains?(message_lower, "captcha") -> :captcha_required
      String.contains?(message_lower, "session") -> :session_error
      true -> :unknown_error
    end
  end

  defp categorize_error(_), do: :unknown_error

  defp maybe_add_session(body, nil), do: body
  defp maybe_add_session(body, session), do: Map.put(body, :session, session)

  defp maybe_add_cookies(body, nil), do: body
  defp maybe_add_cookies(body, []), do: body

  defp maybe_add_cookies(body, cookies) when is_list(cookies) do
    Map.put(body, :cookies, cookies)
  end

  defp maybe_add_proxy(body, nil), do: body
  defp maybe_add_proxy(body, proxy), do: Map.put(body, :proxy, %{url: proxy})

  defp maybe_add_post_data(body, nil), do: body
  defp maybe_add_post_data(body, post_data), do: Map.put(body, :postData, post_data)
end
