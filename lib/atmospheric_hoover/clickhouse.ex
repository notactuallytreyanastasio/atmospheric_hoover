defmodule AtmosphericHoover.Clickhouse do
  @moduledoc """
  ClickHouse client for storing and querying Bluesky posts.
  Uses the HTTP interface with Req. No buffering - let Broadway handle batching.
  """

  require Logger

  @base_url "http://localhost:8123"
  @database "bluesky"

  # Client API - no GenServer needed, just direct HTTP calls

  @doc """
  Insert a batch of posts into ClickHouse. Called directly from Broadway batch handler.
  """
  def insert_posts(posts) when is_list(posts) do
    if posts == [] do
      :ok
    else
      rows =
        posts
        |> Enum.map(&post_to_row/1)
        |> Enum.join("\n")

      url = "#{@base_url}/?database=#{@database}&query=INSERT%20INTO%20posts%20FORMAT%20JSONEachRow"

      case Req.post(url, body: rows, receive_timeout: 30_000) do
        {:ok, %{status: 200}} ->
          :ok

        {:ok, %{status: status, body: body}} ->
          Logger.error("ClickHouse insert failed (#{status}): #{String.slice(body, 0, 200)}")
          {:error, body}

        {:error, reason} ->
          Logger.error("ClickHouse insert error: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Insert a single post (convenience wrapper).
  """
  def insert_post(post) do
    insert_posts([post])
  end

  @doc """
  Execute a raw query and return results.
  """
  def query(sql, opts \\ []) do
    format = Keyword.get(opts, :format, "JSONEachRow")
    url = "#{@base_url}/?database=#{@database}"

    case Req.post(url, body: sql <> " FORMAT #{format}", receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, parse_response(body, format)}

      {:ok, %{status: status, body: body}} ->
        {:error, "ClickHouse error (#{status}): #{body}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Execute a command (no response expected).
  """
  def execute(sql) do
    url = "#{@base_url}/?database=#{@database}"

    case Req.post(url, body: sql, receive_timeout: 60_000) do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status, body: body}} -> {:error, "ClickHouse error (#{status}): #{body}"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Get post count.
  """
  def post_count do
    case query("SELECT count() as count FROM posts", format: "JSONEachRow") do
      {:ok, [%{"count" => count}]} -> {:ok, count}
      {:ok, _} -> {:ok, 0}
      error -> error
    end
  end

  @doc """
  Get posts by user handle.
  """
  def posts_by_user(handle, limit \\ 100) do
    query("SELECT * FROM posts WHERE handle = '#{escape(handle)}' ORDER BY created_at DESC LIMIT #{limit}")
  end

  @doc """
  Get top posters in the last N hours.
  """
  def top_posters(hours \\ 24, limit \\ 20) do
    query("""
    SELECT
      handle,
      count() as post_count,
      uniq(hashtags) as unique_hashtags
    FROM posts
    WHERE created_at >= now() - INTERVAL #{hours} HOUR
    GROUP BY handle
    ORDER BY post_count DESC
    LIMIT #{limit}
    """)
  end

  @doc """
  Get language distribution in the last N hours.
  """
  def language_stats(hours \\ 24) do
    query("""
    SELECT
      arrayJoin(langs) as lang,
      count() as count
    FROM posts
    WHERE created_at >= now() - INTERVAL #{hours} HOUR
    GROUP BY lang
    ORDER BY count DESC
    LIMIT 50
    """)
  end

  @doc """
  Get trending hashtags in the last N hours.
  """
  def trending_hashtags(hours \\ 1, limit \\ 50) do
    query("""
    SELECT
      arrayJoin(hashtags) as hashtag,
      count() as count
    FROM posts
    WHERE created_at >= now() - INTERVAL #{hours} HOUR
      AND length(hashtags) > 0
    GROUP BY hashtag
    ORDER BY count DESC
    LIMIT #{limit}
    """)
  end

  @doc """
  Get posts per minute rate for the last N minutes.
  """
  def posts_per_minute(minutes \\ 60) do
    query("""
    SELECT
      toStartOfMinute(created_at) as minute,
      count() as count
    FROM posts
    WHERE created_at >= now() - INTERVAL #{minutes} MINUTE
    GROUP BY minute
    ORDER BY minute
    """)
  end

  @doc """
  Backfill posts from PostgreSQL firehose_events table.
  """
  def backfill_from_postgres(batch_size \\ 10_000) do
    alias AtmosphericHoover.Repo
    import Ecto.Query

    Logger.info("Starting ClickHouse backfill from PostgreSQL...")

    # Get total count
    total =
      Repo.one(
        from(e in "firehose_events",
          where: e.collection == "app.bsky.feed.post" and e.operation == "create",
          select: count()
        )
      )

    Logger.info("Found #{total} posts to backfill")

    # Process in batches
    stream =
      from(e in "firehose_events",
        where: e.collection == "app.bsky.feed.post" and e.operation == "create",
        select: %{
          did: e.did,
          cid: e.cid,
          rkey: e.rkey,
          record: e.record,
          inserted_at: e.inserted_at
        },
        order_by: [asc: e.id]
      )
      |> Repo.stream(max_rows: batch_size)

    Repo.transaction(
      fn ->
        stream
        |> Stream.chunk_every(batch_size)
        |> Stream.with_index()
        |> Enum.each(fn {batch, idx} ->
          posts = Enum.map(batch, &postgres_record_to_post/1)
          insert_posts(posts)
          Logger.info("Backfilled batch #{idx + 1} (#{(idx + 1) * batch_size}/#{total})")
        end)
      end,
      timeout: :infinity
    )

    Logger.info("Backfill complete!")
    {:ok, total}
  end

  # Private functions

  defp post_to_row(post) do
    # Format created_at for ClickHouse DateTime64(3) - ISO8601 format
    created_at = case post[:created_at] do
      %DateTime{} = dt -> DateTime.to_iso8601(dt)
      nil -> nil
      other -> other
    end

    row = %{
      did: post[:did] || "",
      handle: post[:handle] || "",
      display_name: post[:display_name] || "",
      text: post[:text] || "",
      langs: post[:langs] || [],
      hashtags: post[:hashtags] || [],
      cid: post[:cid] || "",
      uri: post[:uri] || "",
      reply_parent: post[:reply_parent] || "",
      reply_root: post[:reply_root] || "",
      has_images: if(post[:has_images], do: 1, else: 0),
      has_video: if(post[:has_video], do: 1, else: 0),
      has_external_link: if(post[:has_external_link], do: 1, else: 0)
    }

    # Only include created_at if we have it (let ClickHouse default otherwise)
    row = if created_at, do: Map.put(row, :created_at, created_at), else: row

    Jason.encode!(row)
  end

  defp postgres_record_to_post(row) do
    record = row.record || %{}

    %{
      did: row.did || "",
      handle: "",
      display_name: "",
      text: record["text"] || "",
      langs: record["langs"] || [],
      hashtags: extract_hashtags_from_record(record),
      cid: row.cid || "",
      uri: "at://#{row.did}/app.bsky.feed.post/#{row.rkey}",
      reply_parent: get_in(record, ["reply", "parent", "uri"]) || "",
      reply_root: get_in(record, ["reply", "root", "uri"]) || "",
      has_images: has_images_record?(record),
      has_video: has_video_record?(record),
      has_external_link: has_external_record?(record),
      created_at: record["created_at"] || record["createdAt"]
    }
  end

  defp extract_hashtags_from_record(%{"facets" => facets}) when is_list(facets) do
    facets
    |> Enum.flat_map(fn facet ->
      case facet do
        %{"features" => features} when is_list(features) -> features
        _ -> []
      end
    end)
    |> Enum.filter(fn f ->
      case f do
        %{"$type" => "app.bsky.richtext.facet#tag"} -> true
        _ -> false
      end
    end)
    |> Enum.map(fn f -> f["tag"] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&String.downcase/1)
  end

  defp extract_hashtags_from_record(_), do: []

  defp has_images_record?(%{"embed" => %{"$type" => "app.bsky.embed.images"}}), do: true
  defp has_images_record?(%{"embed" => %{"$type" => "app.bsky.embed.recordWithMedia", "media" => %{"$type" => "app.bsky.embed.images"}}}), do: true
  defp has_images_record?(_), do: false

  defp has_video_record?(%{"embed" => %{"$type" => "app.bsky.embed.video"}}), do: true
  defp has_video_record?(_), do: false

  defp has_external_record?(%{"embed" => %{"$type" => "app.bsky.embed.external"}}), do: true
  defp has_external_record?(_), do: false

  defp parse_response("", _format), do: []

  defp parse_response(body, "JSONEachRow") when is_binary(body) do
    body
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  defp parse_response(body, _format), do: body

  defp escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
  end
end
