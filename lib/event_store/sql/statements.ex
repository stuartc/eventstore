defmodule EventStore.Sql.Statements do
  @moduledoc """
  PostgreSQL statements to intialize the event store schema and read/write streams and events.
  """

  def initializers do
    [
      create_streams_table,
      create_stream_uuid_index,
      create_events_table,
      create_event_stream_id_index,
      create_event_stream_id_and_version_index,
      create_subscriptions_table,
      create_subscription_index,
    ]
  end

  def create_streams_table do
"""
CREATE TABLE streams
(
    stream_id BIGSERIAL PRIMARY KEY NOT NULL,
    stream_uuid text NOT NULL,
    stream_type text NOT NULL,
    created_at timestamp NOT NULL
);
"""
  end

  def create_stream_uuid_index do
"""
CREATE UNIQUE INDEX ix_streams_stream_uuid ON streams (stream_uuid);
"""
  end

  def truncate_tables do
"""
TRUNCATE TABLE subscriptions, streams, events
RESTART IDENTITY;
"""
  end

  def create_events_table do
"""
CREATE TABLE events
(
    event_id BIGSERIAL PRIMARY KEY NOT NULL,
    stream_id bigint NOT NULL,
    stream_version bigint NOT NULL,
    event_type text NOT NULL,
    correlation_id text,
    headers bytea NULL,
    payload bytea NOT NULL,
    created_at timestamp NOT NULL
);
"""
  end

  def create_event_stream_id_index do
"""
CREATE INDEX ix_events_stream_id ON events (stream_id);
"""
  end

  def create_event_stream_id_and_version_index do
"""
CREATE UNIQUE INDEX ix_events_stream_id_stream_version ON events (stream_id, stream_version DESC);
"""
  end

  def create_subscriptions_table do
"""
CREATE TABLE subscriptions
(
    subscription_id BIGSERIAL PRIMARY KEY NOT NULL,
    stream_uuid text NOT NULL,
    subscription_name text NOT NULL,
    last_seen_event_id bigint NULL,
    last_seen_stream_version bigint NULL,
    created_at timestamp NOT NULL
);
"""
  end

  def create_subscription_index do
"""
CREATE UNIQUE INDEX ix_subscriptions_stream_uuid_subscription_name ON subscriptions (stream_uuid, subscription_name);
"""
  end

  def create_stream do
"""
INSERT INTO streams (stream_uuid, stream_type, created_at)
VALUES ($1, $2, NOW())
RETURNING stream_id;
"""
  end

  def create_events(number_of_events \\ 1) do
    insert = "INSERT INTO events (stream_id, stream_version, created_at, correlation_id, event_type, headers, payload) VALUES"

    params = 1..number_of_events
    |> Enum.map(fn event_number ->
      index = (event_number - 1) * 6
      "($#{index + 1}, $#{index + 2}, NOW(), $#{index + 3}, $#{index + 4}, $#{index + 5}, $#{index + 6})"
    end)
    |> Enum.join(",")

    returning = "RETURNING event_id, created_at"

    insert <> " " <> params <> " " <> returning <> ";"
  end

  def create_subscription do
"""
INSERT INTO subscriptions (stream_uuid, subscription_name, created_at)
VALUES ($1, $2, NOW())
RETURNING subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at;
"""
  end

  def delete_subscription do
"""
DELETE FROM subscriptions
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def ack_last_seen_event do
"""
UPDATE subscriptions
SET last_seen_event_id = $3, last_seen_stream_version = $4
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def query_all_subscriptions do
"""
SELECT subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at
FROM subscriptions
ORDER BY created_at;
"""
  end

  def query_get_subscription do
"""
SELECT subscription_id, stream_uuid, subscription_name, last_seen_event_id, last_seen_stream_version, created_at
FROM subscriptions
WHERE stream_uuid = $1 AND subscription_name = $2;
"""
  end

  def query_stream_id do
"""
SELECT stream_id
FROM streams
WHERE stream_uuid = $1;
"""
  end

  def query_latest_version do
"""
SELECT stream_version
FROM events
WHERE stream_id = $1
ORDER BY stream_version DESC
LIMIT 1;
"""
  end

  def query_latest_event_id do
"""
SELECT COALESCE(MAX(event_id), 0)
FROM events;
"""
  end

  def read_events_forward do
"""
SELECT
  event_id,
  stream_id,
  stream_version,
  event_type,
  correlation_id,
  headers,
  payload,
  created_at
FROM events
WHERE stream_id = $1 and stream_version >= $2
ORDER BY stream_version ASC;
"""
  end

  def read_all_events_forward do
"""
SELECT
  event_id,
  stream_id,
  stream_version,
  event_type,
  correlation_id,
  headers,
  payload,
  created_at
FROM events
WHERE event_id >= $1
ORDER BY event_id ASC;
"""
  end
end
