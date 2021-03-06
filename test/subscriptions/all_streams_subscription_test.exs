defmodule EventStore.Subscriptions.AllStreamsSubscriptionTest do
  use EventStore.StorageCase
  doctest EventStore.Subscriptions.AllStreamsSubscription

  alias EventStore.{EventFactory,Storage,Subscriber}
  alias EventStore.Subscriptions.AllStreamsSubscription

  @all_stream "$all"
  @subscription_name "test_subscription"

  test "create subscription to stream" do
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)

    assert subscription.state == :catching_up
    assert subscription.data.subscription_name == @subscription_name
    assert subscription.data.subscriber == subscriber
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, no persisted events" do
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 0
  end

  test "catch-up subscription, unseen persisted events" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, subscriber} = Subscriber.start_link(self)
    {:ok, _} = Storage.append_to_stream(stream_uuid, 0, events)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed
    assert subscription.data.last_seen_event_id == 3

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(events)
    assert payload(received_events) == payload(events)
  end

  test "notify events" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_recorded_events(1, stream_uuid)
    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up
      |> AllStreamsSubscription.notify_events(events)

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}

    assert correlation_id(received_events) == correlation_id(events)
    assert payload(received_events) == payload(events)
  end

  test "ack notified events" do
    stream_uuid = UUID.uuid4()
    events = EventFactory.create_events(3)

    {:ok, _} = Storage.append_to_stream(stream_uuid, 0, events)

    {:ok, subscriber} = Subscriber.start_link(self)

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    assert subscription.state == :subscribed

    assert_receive {:events, received_events}
    assert length(received_events) == 3

    subscription =
      AllStreamsSubscription.new
      |> AllStreamsSubscription.subscribe(@all_stream, @subscription_name, subscriber)
      |> AllStreamsSubscription.catch_up

    # should not receive already seen events
    refute_receive {:events, _received_events}

    assert subscription.state == :subscribed
  end

  defp correlation_id(events), do: Enum.map(events, &(&1.correlation_id))
  defp payload(events), do: Enum.map(events, &(&1.payload))
end
