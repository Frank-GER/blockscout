defmodule BlockScoutWeb.RealtimeEventHandler do
  @moduledoc """
  Subscribing process for broadcast events from realtime.
  """

  use GenServer

  alias BlockScoutWeb.Notifier
  alias Explorer.Chain.Events.Subscriber
  alias Explorer.Counters.Helper

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    Helper.create_cache_table(:last_broadcasted_block)
    Subscriber.to(:address_coin_balances, :realtime)
    Subscriber.to(:addresses, :realtime)
    Subscriber.to(:block_rewards, :realtime)
    Subscriber.to(:blocks, :realtime)
    Subscriber.to(:internal_transactions, :realtime)
    Subscriber.to(:internal_transactions, :on_demand)
    Subscriber.to(:optimism_deposits, :realtime)
    Subscriber.to(:token_transfers, :realtime)
    Subscriber.to(:transactions, :realtime)
    Subscriber.to(:addresses, :on_demand)
    Subscriber.to(:address_coin_balances, :on_demand)
    Subscriber.to(:address_current_token_balances, :on_demand)
    Subscriber.to(:address_token_balances, :on_demand)
    Subscriber.to(:contract_verification_result, :on_demand)
    Subscriber.to(:token_total_supply, :on_demand)
    Subscriber.to(:changed_bytecode, :on_demand)
    Subscriber.to(:smart_contract_was_verified, :on_demand)
    # Does not come from the indexer
    Subscriber.to(:exchange_rate)
    Subscriber.to(:transaction_stats)
    {:ok, []}
  end

  @impl true
  def handle_info(event, state) do
    Notifier.handle_event(event)
    {:noreply, state}
  end
end
