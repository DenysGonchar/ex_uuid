defmodule ExUUID.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Starts a worker by calling: ExUUID.Worker.start_link([])
      ExUUID.Worker
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ExUUID.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

defmodule ExUUID.Worker do
  use GenServer
  import Bitwise

  @node_id {:ex_uuid, :node_id}
  @ets_name :ex_uuid

  # Client

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  # Server (callbacks)

  @impl true
  def init(:ok) do
    maybe_generate_node_id()

    :ets.new(@ets_name, [
      :set,
      :named_table,
      :protected,
      read_concurrency: true,
      keypos: 1
    ])

    for n <- [node() | :erlang.nodes()] do
      :ets.insert_new(@ets_name, {node_hash(n), n})
    end

    :net_kernel.monitor_nodes(true, node_type: :all)
    {:ok, :ok}
  end

  defp maybe_generate_node_id do
    node_hash = node_hash(node())
    <<rnd_hi::6, _::2, rnd_low::8>> = :crypto.strong_rand_bytes(2)
    ## locally administered multicast MAC address
    default_node_id = <<rnd_hi::6, 3::2, rnd_low::8, node_hash::32>>
    node_id = :persistent_term.get(@node_id, default_node_id)
    :persistent_term.put(@node_id, node_id)
  end

  defp node_hash(node) when is_atom(node) do
    :erlang.phash2(node, 1 <<< 32)
  end

  @impl true
  def handle_info({:nodeup, node, _}, state) do
    :ets.insert_new(@ets_name, {node_hash(node), node})
    state
  end

  def handle_info({:nodedown, node, _}, state) do
    :ets.delete_object(@ets_name, {node_hash(node), node})
    state
  end
end
