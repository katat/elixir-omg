defmodule OmiseGOWatcher.Integration.TestHelper do
  @moduledoc """
  Common helper functions that are useful when integration-testing the watcher
  """

  alias OmiseGO.Eth
  import OmiseGOWatcher.TestHelper

  def compose_utxo_exit(blknum, txindex, oindex) do
    decoded_resp = rest_call(:get, "account/utxo/compose_exit?blknum=#{blknum}&txindex=#{txindex}&oindex=#{oindex}")

    {:ok, txbytes} = Base.decode16(decoded_resp["txbytes"], case: :mixed)
    {:ok, proof} = Base.decode16(decoded_resp["proof"], case: :mixed)
    {:ok, sigs} = Base.decode16(decoded_resp["sigs"], case: :mixed)

    %{
      utxo_pos: decoded_resp["utxo_pos"],
      txbytes: txbytes,
      proof: proof,
      sigs: sigs
    }
  end

  def wait_until_block_getter_fetches_block(block_nr, timeout) do
    fn ->
      Eth.WaitFor.repeat_until_ok(wait_for_block(block_nr))
    end
    |> Task.async()
    |> Task.await(timeout)

    # TODO write to db seems to be async and wait_until_block_getter_fetches_block
    # returns too early

    Process.sleep(100)
  end

  defp wait_for_block(block_nr) do
    fn ->
      case GenServer.call(OmiseGOWatcher.BlockGetter, :get_height) < block_nr do
        true -> :repeat
        false -> {:ok, block_nr}
      end
    end
  end
end
