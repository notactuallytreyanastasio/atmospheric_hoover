defmodule AtmosphericHoover.Bluesky.ProfileFetcher do
  @moduledoc """
  Fetches user profiles from the Bluesky public API.

  This module provides a functional interface to the Bluesky `app.bsky.actor.getProfile`
  endpoint. It uses the Req library for HTTP requests.

  ## API Endpoint

  Uses the public Bluesky API:
  ```
  GET https://public.api.bsky.app/xrpc/app.bsky.actor.getProfile?actor=<did>
  ```

  ## Rate Limiting

  The public API has rate limits. This module includes configurable retry
  behavior and respects rate limit headers.

  ## Examples

      iex> ProfileFetcher.fetch_profile("did:plc:z72i7hdynmk6r22z27h6tvur")
      {:ok, %{"did" => "did:plc:z72i7hdynmk6r22z27h6tvur", "handle" => "bsky.app", ...}}

      iex> ProfileFetcher.fetch_profile("invalid-did")
      {:error, "Profile not found"}
  """

  require Logger

  @base_url "https://public.api.bsky.app/xrpc"
  @default_timeout 10_000
  @default_retries 2

  @typedoc "Profile fetch result"
  @type fetch_result :: {:ok, map()} | {:error, String.t()}

  @doc """
  Fetches a user profile by DID or handle.

  ## Parameters

  * `actor` - DID (e.g., "did:plc:abc123") or handle (e.g., "alice.bsky.social")
  * `opts` - Options:
    * `:timeout` - Request timeout in ms (default: #{@default_timeout})
    * `:retries` - Number of retries on failure (default: #{@default_retries})

  ## Returns

  * `{:ok, profile}` - Profile map from the API
  * `{:error, reason}` - Error message

  ## Examples

      # Fetch by DID
      iex> ProfileFetcher.fetch_profile("did:plc:z72i7hdynmk6r22z27h6tvur")
      {:ok, %{"did" => ..., "handle" => ..., "displayName" => ...}}

      # Fetch by handle
      iex> ProfileFetcher.fetch_profile("bsky.app")
      {:ok, %{"did" => ..., "handle" => "bsky.app", ...}}
  """
  @spec fetch_profile(String.t(), keyword()) :: fetch_result()
  def fetch_profile(actor, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @default_retries)

    url = "#{@base_url}/app.bsky.actor.getProfile"

    case Req.get(url,
           params: [actor: actor],
           receive_timeout: timeout,
           retry: :transient,
           max_retries: retries
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: 400, body: %{"error" => "InvalidRequest"}}} ->
        {:error, "Invalid actor identifier"}

      {:ok, %Req.Response{status: 404}} ->
        {:error, "Profile not found"}

      {:ok, %Req.Response{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        {:error, "Rate limited, retry after #{retry_after}s"}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg = extract_error(body) || "HTTP #{status}"
        {:error, error_msg}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, "Request timeout"}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, "Transport error: #{inspect(reason)}"}

      {:error, exception} ->
        {:error, "Request failed: #{inspect(exception)}"}
    end
  end

  @doc """
  Fetches multiple profiles in batch.

  Fetches profiles sequentially with a small delay between requests
  to be respectful of rate limits.

  ## Parameters

  * `actors` - List of DIDs or handles
  * `opts` - Options passed to `fetch_profile/2`, plus:
    * `:delay_ms` - Delay between requests in ms (default: 100)

  ## Returns

  List of `{actor, result}` tuples.

  ## Examples

      iex> ProfileFetcher.fetch_profiles(["did:plc:abc", "did:plc:xyz"])
      [{"did:plc:abc", {:ok, %{...}}}, {"did:plc:xyz", {:error, "not found"}}]
  """
  @spec fetch_profiles([String.t()], keyword()) :: [{String.t(), fetch_result()}]
  def fetch_profiles(actors, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 100)
    fetch_opts = Keyword.drop(opts, [:delay_ms])

    actors
    |> Enum.map(fn actor ->
      result = fetch_profile(actor, fetch_opts)

      # Small delay between requests to avoid rate limiting
      if delay_ms > 0, do: Process.sleep(delay_ms)

      {actor, result}
    end)
  end

  # Extract retry-after header value from Req headers map
  defp get_retry_after(headers) when is_map(headers) do
    case Map.get(headers, "retry-after") do
      [value | _] -> String.to_integer(value)
      nil -> 60
    end
  end

  # Extract error message from API response body
  defp extract_error(%{"error" => error, "message" => message}), do: "#{error}: #{message}"
  defp extract_error(%{"error" => error}), do: error
  defp extract_error(%{"message" => message}), do: message
  defp extract_error(_), do: nil
end
