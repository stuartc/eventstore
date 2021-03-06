defmodule EventStore.Streams.Stream do
  @moduledoc """
  An event stream
  """

  use GenServer
  require Logger

  alias EventStore.Storage
  alias EventStore.Streams.Stream

  defstruct stream_uuid: nil

  def start_link(stream_uuid) do
    GenServer.start_link(__MODULE__, %Stream{
      stream_uuid: stream_uuid
    })
  end

  @doc """
  Append the given list of events to the stream, expected version is used for optimistic concurrency
  
  Each `Stream` is a GenServer process, so writes to a single logical stream will always be serialized.
  """
  def append_to_stream(stream, expected_version, events) do
    GenServer.call(stream, {:append_to_stream, expected_version, events})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_call({:append_to_stream, expected_version, events}, _from, %Stream{stream_uuid: stream_uuid} = state) do
    reply = Storage.append_to_stream(stream_uuid, expected_version, events)
    {:reply, reply, state}
  end
end
