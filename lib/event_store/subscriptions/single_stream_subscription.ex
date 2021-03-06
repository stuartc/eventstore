defmodule EventStore.Subscriptions.SingleStreamSubscription do
  require Logger

  defmodule SubscriptionData do
    defstruct stream_uuid: nil,
              subscription_name: nil,
              subscriber: nil,
              last_seen_stream_version: 0
  end

  alias EventStore.{RecordedEvent,Storage}
  alias EventStore.Subscriptions.SingleStreamSubscription

  use Fsm, initial_state: :initial, initial_data: %SubscriptionData{}

  defstate initial do
    defevent subscribe(stream_uuid, subscription_name, subscriber), data: %SubscriptionData{} = data do
      case subscribe_to_stream(stream_uuid, subscription_name) do
        {:ok, subscription} ->
          data = %SubscriptionData{data |
            stream_uuid: stream_uuid,
            subscription_name: subscription_name,
            subscriber: subscriber,
            last_seen_stream_version: (subscription.last_seen_stream_version || 0)
          }
          next_state(:catching_up, data)
        {:error, reason} ->
          next_state(:failed, data)
      end
    end
  end

  defstate catching_up do
    defevent catch_up, data: %SubscriptionData{stream_uuid: stream_uuid, last_seen_stream_version: last_seen_stream_version} = data do
      case query_latest_stream_version(stream_uuid) do
        0 ->
          # no events
          next_state(:subscribed, data)

        ^last_seen_stream_version ->
          # already seen latest stream version
          next_state(:subscribed, data)

        latest_stream_version ->
          # must catch-up with all unseen events for stream
          data = catch_up_to_stream_version(data)

          next_state(:subscribed, data)
      end
    end

    # ignore event notifications while catching up; but remember the latest event id
    defevent notify_events(events), data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end
  end

  defstate subscribed do
    # notify events for single stream subscription
    defevent notify_events(events), data: %SubscriptionData{stream_uuid: stream_uuid, last_seen_stream_version: last_seen_stream_version} = data do
      expected_stream_version = last_seen_stream_version + 1

      case first_stream_version(events) do
        ^expected_stream_version ->
          last_event = List.last(events)

          notify_subscriber(data, events)
          ack_events(data, events, last_event.stream_version)

          data = %SubscriptionData{data |
            last_seen_stream_version: last_event.stream_version
          }

          next_state(:subscribed, data)
        _ ->
          # must catch-up with all unseen events
          next_state(:catching_up, data)
      end
    end

    defevent catch_up, data: %SubscriptionData{} = data do
      next_state(:catching_up, data)
    end

    defevent unsubscribe, data: %SubscriptionData{} = data do
      next_state(:unsubscribed, data)
    end
  end

  defstate unsubscribed do
  end

  defstate failed do
  end

  defp subscribe_to_stream(stream_uuid, subscription_name) do
    Storage.subscribe_to_stream(stream_uuid, subscription_name)
  end

  defp query_latest_stream_version(stream_uuid) do
    {:ok, latest_stream_version} = Storage.latest_stream_version(stream_uuid)
    latest_stream_version
  end

  defp catch_up_to_stream_version(%SubscriptionData{stream_uuid: stream_uuid, last_seen_stream_version: last_seen_stream_version} = data) do
    last_event = case unseen_events(stream_uuid, last_seen_stream_version) do
      {:ok, events} ->
        # chunk events by correlation id
        events
        |> Enum.chunk_by(fn event -> event.correlation_id end)
        |> Enum.map(fn events_by_correlation_id ->
          last_event = List.last(events_by_correlation_id)

          notify_subscriber(data, events_by_correlation_id)
          ack_events(data, events_by_correlation_id, last_event.stream_version)

          last_event
        end)
        |> Enum.reduce(fn (last_event, _) -> last_event end)
    end

    data = %SubscriptionData{data | last_seen_stream_version: last_event.stream_version}
  end

  defp unseen_events(stream_uuid, last_seen_stream_version) do
    start_version = last_seen_stream_version + 1

    Storage.read_stream_forward(stream_uuid, start_version)
  end

  defp notify_subscriber(%SubscriptionData{subscriber: subscriber} = data, events) do
    send(subscriber, {:events, events})
  end

  defp ack_events(%SubscriptionData{stream_uuid: stream_uuid, subscription_name: subscription_name} = data, events, last_stream_version) do
    Storage.ack_last_seen_event(stream_uuid, subscription_name, nil, last_stream_version)
  end

  defp first_event_id([first_event|_]) do
    first_event.event_id
  end

  defp first_stream_version([first_event|_]) do
    first_event.stream_version
  end
end
