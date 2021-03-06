defmodule EventStore.Publisher do
  @moduledoc """
  Publish events appended to all streams to subscriptions process, ordered by event id
  """

  use GenServer
  require Logger

  alias EventStore.{Publisher,PendingEvents}
  alias EventStore.Subscriptions

  defmodule PendingEvents do
    defstruct initial_event_id: nil, last_event_id: nil, stream_uuid: nil, events: []
  end

  defstruct last_published_event_id: 0, pending_events: %{}

  def start_link do
    GenServer.start_link(__MODULE__, %Publisher{}, name: __MODULE__)
  end

  def notify_events(stream_uuid, events) do
    GenServer.cast(__MODULE__, {:notify_events, stream_uuid, events})
  end

  def init(%Publisher{} = state) do
    {:ok, state}
  end

  def handle_cast({:notify_events, stream_uuid, events}, %Publisher{last_published_event_id: last_published_event_id, pending_events: pending_events} = state) do
    expected_event_id = last_published_event_id + 1
    initial_event_id = first_event_id(events)
    last_event_id = last_event_id(events)

    state = case initial_event_id do
      ^expected_event_id ->
        # immediately notify subscribers as events are in expected order
        Subscriptions.notify_events(stream_uuid, events)

        %Publisher{state | last_published_event_id: last_event_id }

      initial_event_id ->
        # append to pending events as they are out of order
        pending = %PendingEvents{
          initial_event_id: initial_event_id,
          last_event_id: last_event_id,
          stream_uuid: stream_uuid,
          events: events
        }

        # attempt to publish pending events
        GenServer.cast(self, {:notify_pending_events})

        %Publisher{state | pending_events: Map.put(pending_events, initial_event_id, pending) }
    end

    {:noreply, state}
  end

  def handle_cast({:notify_pending_events}, %Publisher{last_published_event_id: last_published_event_id, pending_events: pending_events} = state) do
    next_event_id = last_published_event_id + 1

    state = case Map.get(pending_events, next_event_id) do
      %PendingEvents{stream_uuid: stream_uuid, events: events, last_event_id: last_event_id} ->
        Subscriptions.notify_events(stream_uuid, events)

        %Publisher{state | last_published_event_id: last_event_id, pending_events: Map.delete(pending_events, next_event_id) }
      nil -> state
    end

    {:noreply, state}
  end

  defp first_event_id([first|_]), do: first.event_id
  defp last_event_id(events), do: List.last(events).event_id
end
