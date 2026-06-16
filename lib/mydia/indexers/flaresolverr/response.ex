defmodule Mydia.Indexers.FlareSolverr.Response do
  @moduledoc """
  Struct representing a FlareSolverr API response.

  FlareSolverr returns responses in the following format:
  ```json
  {
    "status": "ok",
    "message": "Challenge solved!",
    "solution": {
      "url": "https://example.com/page",
      "status": 200,
      "headers": {"content-type": "text/html"},
      "response": "<html>...</html>",
      "cookies": [
        {"name": "cf_clearance", "value": "...", "domain": ".example.com", ...}
      ],
      "userAgent": "Mozilla/5.0..."
    },
    "startTimestamp": 1234567890123,
    "endTimestamp": 1234567890456,
    "version": "3.3.21"
  }
  ```
  """

  @type cookie :: %{
          name: String.t(),
          value: String.t(),
          domain: String.t(),
          path: String.t(),
          expires: float() | nil,
          http_only: boolean(),
          secure: boolean(),
          same_site: String.t() | nil
        }

  @type solution :: %{
          url: String.t(),
          status: integer(),
          headers: map(),
          response: String.t(),
          cookies: [cookie()],
          user_agent: String.t()
        }

  @type t :: %__MODULE__{
          status: String.t(),
          message: String.t() | nil,
          solution: solution() | nil,
          start_timestamp: integer() | nil,
          end_timestamp: integer() | nil,
          version: String.t() | nil
        }

  defstruct [:status, :message, :solution, :start_timestamp, :end_timestamp, :version]

  @doc """
  Parses a FlareSolverr JSON response into a Response struct.
  """
  @spec from_json(map()) :: {:ok, t()} | {:error, String.t()}
  def from_json(%{"status" => status} = json) do
    response = %__MODULE__{
      status: status,
      message: json["message"],
      solution: parse_solution(json["solution"]),
      start_timestamp: json["startTimestamp"],
      end_timestamp: json["endTimestamp"],
      version: json["version"]
    }

    {:ok, response}
  end

  def from_json(_), do: {:error, "Invalid FlareSolverr response format"}

  @doc """
  Returns the HTML body from the response.
  """
  @spec body(t()) :: String.t() | nil
  def body(%__MODULE__{solution: %{response: response}}), do: response
  def body(_), do: nil

  @doc """
  Returns the cookies from the response as a list of cookie maps.
  """
  @spec cookies(t()) :: [cookie()]
  def cookies(%__MODULE__{solution: %{cookies: cookies}}) when is_list(cookies), do: cookies
  def cookies(_), do: []

  @doc """
  Returns the cookies formatted as a Cookie header string.
  """
  @spec cookie_header(t()) :: String.t()
  def cookie_header(%__MODULE__{} = response) do
    response
    |> cookies()
    |> Enum.map_join("; ", fn cookie -> "#{cookie.name}=#{cookie.value}" end)
  end

  @doc """
  Returns the user agent from the response.
  """
  @spec user_agent(t()) :: String.t() | nil
  def user_agent(%__MODULE__{solution: %{user_agent: ua}}), do: ua
  def user_agent(_), do: nil

  @doc """
  Returns the HTTP status code from the solved request.
  """
  @spec http_status(t()) :: integer() | nil
  def http_status(%__MODULE__{solution: %{status: status}}), do: status
  def http_status(_), do: nil

  @doc """
  Returns true if the challenge was solved successfully.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{status: "ok"}), do: true
  def success?(_), do: false

  @doc """
  Returns the time taken to solve the challenge in milliseconds.
  """
  @spec duration_ms(t()) :: integer() | nil
  def duration_ms(%__MODULE__{start_timestamp: start_ts, end_timestamp: end_ts})
      when is_integer(start_ts) and is_integer(end_ts) do
    end_ts - start_ts
  end

  def duration_ms(_), do: nil

  ## Private Functions

  defp parse_solution(nil), do: nil

  defp parse_solution(solution) when is_map(solution) do
    %{
      url: solution["url"],
      status: solution["status"],
      headers: solution["headers"] || %{},
      response: solution["response"],
      cookies: parse_cookies(solution["cookies"]),
      user_agent: solution["userAgent"]
    }
  end

  defp parse_cookies(nil), do: []
  defp parse_cookies(cookies) when is_list(cookies), do: Enum.map(cookies, &parse_cookie/1)
  defp parse_cookies(_), do: []

  defp parse_cookie(cookie) when is_map(cookie) do
    %{
      name: cookie["name"],
      value: cookie["value"],
      domain: cookie["domain"],
      path: cookie["path"] || "/",
      expires: cookie["expires"],
      http_only: cookie["httpOnly"] || false,
      secure: cookie["secure"] || false,
      same_site: cookie["sameSite"]
    }
  end

  defp parse_cookie(_), do: nil
end
