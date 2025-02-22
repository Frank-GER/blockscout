defmodule Indexer.Supervisor do
  @moduledoc """
  Supervisor of all indexer worker supervision trees
  """

  use Supervisor

  alias Indexer.{
    Block,
    PendingOpsCleaner,
    PendingTransactionsSanitizer
  }

  alias Indexer.Block.Catchup, as: BlockCatchup
  alias Indexer.Block.Realtime, as: BlockRealtime
  alias Indexer.Fetcher.TokenInstance.Realtime, as: TokenInstanceRealtime
  alias Indexer.Fetcher.TokenInstance.Retry, as: TokenInstanceRetry
  alias Indexer.Fetcher.TokenInstance.Sanitize, as: TokenInstanceSanitize

  alias Indexer.Fetcher.{
    BlockReward,
    CoinBalance,
    ContractCode,
    EmptyBlocksSanitizer,
    InternalTransaction,
    Optimism,
    OptimismDeposit,
    OptimismOutputRoot,
    OptimismTxnBatch,
    OptimismWithdrawal,
    OptimismWithdrawalEvent,
    PendingBlockOperationsSanitizer,
    PendingTransaction,
    ReplacedTransaction,
    Token,
    TokenBalance,
    TokenTotalSupplyUpdater,
    TokenUpdater,
    TransactionAction,
    UncleBlock,
    Withdrawal
  }

  alias Indexer.Temporary.{
    BlocksTransactionsMismatch,
    UncatalogedTokenTransfers,
    UnclesWithoutIndex
  }

  def child_spec([]) do
    child_spec([[]])
  end

  def child_spec([init_arguments]) do
    child_spec([init_arguments, []])
  end

  def child_spec([_init_arguments, _gen_server_options] = start_link_arguments) do
    default = %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_link_arguments},
      type: :supervisor
    }

    Supervisor.child_spec(default, [])
  end

  def start_link(arguments, gen_server_options \\ []) do
    Supervisor.start_link(__MODULE__, arguments, Keyword.put_new(gen_server_options, :name, __MODULE__))
  end

  @impl Supervisor
  def init(%{memory_monitor: memory_monitor}) do
    json_rpc_named_arguments = Application.fetch_env!(:indexer, :json_rpc_named_arguments)

    named_arguments =
      :indexer
      |> Application.get_all_env()
      |> Keyword.take(
        ~w(blocks_batch_size blocks_concurrency block_interval json_rpc_named_arguments receipts_batch_size
           receipts_concurrency subscribe_named_arguments realtime_overrides)a
      )
      |> Enum.into(%{})
      |> Map.put(:memory_monitor, memory_monitor)
      |> Map.put_new(:realtime_overrides, %{})

    %{
      block_interval: block_interval,
      realtime_overrides: realtime_overrides,
      subscribe_named_arguments: subscribe_named_arguments
    } = named_arguments

    block_fetcher =
      named_arguments
      |> Map.drop(~w(block_interval blocks_concurrency memory_monitor subscribe_named_arguments realtime_overrides)a)
      |> Block.Fetcher.new()

    realtime_block_fetcher =
      named_arguments
      |> Map.drop(~w(block_interval blocks_concurrency memory_monitor subscribe_named_arguments realtime_overrides)a)
      |> Map.merge(Enum.into(realtime_overrides, %{}))
      |> Block.Fetcher.new()

    realtime_subscribe_named_arguments = realtime_overrides[:subscribe_named_arguments] || subscribe_named_arguments

    basic_fetchers =
      [
        # Root fetchers
        {PendingTransaction.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments]]},

        # Async catchup fetchers
        {UncleBlock.Supervisor, [[block_fetcher: block_fetcher, memory_monitor: memory_monitor]]},
        {BlockReward.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {InternalTransaction.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {CoinBalance.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {Token.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {TokenInstanceRealtime.Supervisor, [[memory_monitor: memory_monitor]]},
        {TokenInstanceRetry.Supervisor, [[memory_monitor: memory_monitor]]},
        {TokenInstanceSanitize.Supervisor, [[memory_monitor: memory_monitor]]},
        configure(TransactionAction.Supervisor, [[memory_monitor: memory_monitor]]),
        {ContractCode.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {TokenBalance.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {TokenUpdater.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {ReplacedTransaction.Supervisor, [[memory_monitor: memory_monitor]]},
        {Optimism.Supervisor, [[memory_monitor: memory_monitor]]},
        {OptimismTxnBatch.Supervisor,
         [[memory_monitor: memory_monitor, json_rpc_named_arguments: json_rpc_named_arguments]]},
        {OptimismOutputRoot.Supervisor, [[memory_monitor: memory_monitor]]},
        {OptimismDeposit.Supervisor, [[memory_monitor: memory_monitor]]},
        {OptimismWithdrawal.Supervisor,
         [[memory_monitor: memory_monitor, json_rpc_named_arguments: json_rpc_named_arguments]]},
        {OptimismWithdrawalEvent.Supervisor, [[memory_monitor: memory_monitor]]},

        # Out-of-band fetchers
        {EmptyBlocksSanitizer.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments]]},
        {PendingTransactionsSanitizer, [[json_rpc_named_arguments: json_rpc_named_arguments]]},
        {TokenTotalSupplyUpdater, [[]]},

        # Temporary workers
        {UncatalogedTokenTransfers.Supervisor, [[]]},
        {UnclesWithoutIndex.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {BlocksTransactionsMismatch.Supervisor,
         [[json_rpc_named_arguments: json_rpc_named_arguments, memory_monitor: memory_monitor]]},
        {PendingOpsCleaner, [[], []]},
        {PendingBlockOperationsSanitizer, [[]]},

        # Block fetchers
        configure(BlockRealtime.Supervisor, [
          %{block_fetcher: realtime_block_fetcher, subscribe_named_arguments: realtime_subscribe_named_arguments},
          [name: BlockRealtime.Supervisor]
        ]),
        {BlockCatchup.Supervisor,
         [
           %{block_fetcher: block_fetcher, block_interval: block_interval, memory_monitor: memory_monitor},
           [name: BlockCatchup.Supervisor]
         ]},
        {Withdrawal.Supervisor, [[json_rpc_named_arguments: json_rpc_named_arguments]]}
      ]
      |> List.flatten()

    Supervisor.init(
      basic_fetchers,
      strategy: :one_for_one
    )
  end

  defp configure(process, opts) do
    if Application.get_env(:indexer, process)[:enabled] do
      [{process, opts}]
    else
      []
    end
  end
end
