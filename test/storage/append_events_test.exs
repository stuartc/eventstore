defmodule EventStore.Storage.AppendEventsTest do
  use EventStore.StorageCase
  doctest EventStore.Storage

  alias EventStore.EventFactory
  alias EventStore.Storage

  test "append single event to new stream" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, persisted_events} = Storage.append_to_stream(stream_uuid, 0, events)

    assert length(persisted_events) == 1
    assert hd(persisted_events).event_id == 1
  end

  test "append multiple events to new stream" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, _} = Storage.append_to_stream(stream_uuid, 0, events)
  end

  test "append single event to existing stream" do
    stream_uuid = UUID.uuid4()

    {:ok, events} = Storage.append_to_stream(stream_uuid, 0, EventFactory.create_events(1))
    assert length(events) == 1

    {:ok, events} = Storage.append_to_stream(stream_uuid, 1, EventFactory.create_events(1))
    assert length(events) == 1
  end

  test "append multiple events to existing stream" do
    stream_uuid = UUID.uuid4()

    {:ok, events} = Storage.append_to_stream(stream_uuid, 0, EventFactory.create_events(3))
    assert length(events) == 3

    {:ok, events} = Storage.append_to_stream(stream_uuid, 3, EventFactory.create_events(3))
    assert length(events) == 3
  end

  test "append events to different, new streams" do
    {:ok, events} = Storage.append_to_stream(UUID.uuid4(), 0, EventFactory.create_events(2))
    assert length(events) == 2

    {:ok, events} = Storage.append_to_stream(UUID.uuid4(), 0, EventFactory.create_events(2))
    assert length(events) == 2
  end

  test "append events to different, existing streams" do
    stream1_uuid = UUID.uuid4()
    stream2_uuid = UUID.uuid4()

    {:ok, _} = Storage.append_to_stream(stream1_uuid, 0, EventFactory.create_events(2))
    {:ok, _} = Storage.append_to_stream(stream2_uuid, 0, EventFactory.create_events(2))
    {:ok, _} = Storage.append_to_stream(stream1_uuid, 2, EventFactory.create_events(2))
    {:ok, _} = Storage.append_to_stream(stream2_uuid, 2, EventFactory.create_events(2))
  end

  test "append to new stream, but stream already exists" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:ok, _} = Storage.append_to_stream(stream_uuid, 0, events)
    {:error, :wrong_expected_version} = Storage.append_to_stream(stream_uuid, 0, events)
  end

  test "append to existing stream, but stream does not exist" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(1)

    {:error, :stream_not_found} = Storage.append_to_stream(stream_uuid, 1, events)
  end

  test "append to existing stream, but wrong expected version" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(2)

    {:ok, _} = Storage.append_to_stream(stream_uuid, 0, events)
    {:error, :wrong_expected_version} = Storage.append_to_stream(stream_uuid, 1, events)
  end
end
