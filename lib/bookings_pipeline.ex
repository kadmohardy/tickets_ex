defmodule BookingsPipeline do
  use Broadway

  alias Broadway.Message

  @producer BroadwayRabbitMQ.Producer
  @producer_config [
    queue: "bookings_queue",
    declare: [durable: true],
    on_failure: :reject_and_requeue,
    qos: [prefetch_count: 100]
  ]

  def start_link(_args) do
    # options = [
    #   name: BookingsPipeline,
    #   producer: [module: {@producer, @producer_config}, concurrency: 1],
    #   processors: [
    #     default: [
    #       concurrency: System.schedulers_online() * 2
    #     ]
    #   ]
    # ]
    # Batch processors
    options = [
      name: BookingsPipeline,
      producer: [module: {@producer, @producer_config}],
      processors: [
        default: []
      ],
      batchers: [
        cinema: [batch_size: 75],
        musical: [],
        default: [batch_size: 50]
      ]
    ]

    Broadway.start_link(__MODULE__, options)
  end

  def handle_message(_processor, message, _context) do
    %{data: %{event: event}} = message

    if TicketsEx.tickets_available?(event) do
      case message do
        %{data: %{event: "cinema"}} = message ->
          Broadway.Message.put_batcher(message, :cinema)

        %{data: %{event: "musical"}} = message ->
          Broadway.Message.put_batcher(message, :musical)

        message ->
          message
      end
    else
      Broadway.Message.failed(message, "bookings-closed")
    end
  end

  def prepare_messages(messages, _context) do
    messages =
      Enum.map(messages, fn message ->
        Message.update_data(message, fn data ->
          [event, user_id] = String.split(data, ",")
          %{event: event, user_id: user_id}
        end)
      end)

    users =
      messages
      |> Enum.map(& &1.data.user_id)
      |> TicketsEx.users_by_ids()

    Enum.map(messages, fn message ->
      Broadway.Message.update_data(message, fn data ->
        user = Enum.find(users, &(&1.id == data.user_id))

        Map.put(data, :user, user)
      end)
    end)
  end

  def handle_failed(messages, _context) do
    IO.inspect(messages, label: "Failed messages")

    Enum.map(messages, fn
      %{status: {:failed, "bookings-closed"}} = message ->
        Broadway.Message.configure_ack(message, on_failure: :reject)

      message ->
        message
    end)
  end

  def handle_batch(_batcher, messages, batch_info, _context) do
    IO.puts("#{inspect(self())} Batch #{batch_info.batcher} #{batch_info.batch_key}")

    messages
    |> TicketsEx.insert_all_tickets()
    |> Enum.each(&send_notification/1)

    messages
  end

  defp send_notification(message) do
    channel = message.metadata.amqp_channel
    payload = "email, #{message.data.user.email}"
    AMQP.Basic.publish(channel, "", "notifications_queue", payload)
  end
end
