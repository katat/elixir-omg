# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.Eth.DevHelpers do
  @moduledoc """
  Helpers used when setting up development environment and test fixtures, related to contracts and ethereum.
  Run against `geth --dev` and similar.
  """

  alias OMG.API.Crypto
  alias OMG.Eth
  alias OMG.Eth.WaitFor, as: WaitFor

  import OMG.Eth.Encoding

  # about 4 Ethereum blocks on "realistic" networks, use to timeout synchronous operations in demos on testnets
  @about_4_blocks_time 60_000

  @one_hundred_eth trunc(:math.pow(10, 18) * 100)

  @doc """
  Prepares the developer's environment with respect to the root chain contract and its configuration within
  the application.

   - `root_path` should point to `elixir-omg` root or wherever where `./contracts/build` holds the compiled contracts
  """
  def prepare_env!(root_path \\ "./") do
    {:ok, _} = Application.ensure_all_started(:ethereumex)
    {:ok, authority} = create_and_fund_authority_addr()
    {:ok, txhash, contract_addr} = Eth.RootChain.create_new(root_path, authority)
    %{contract_addr: contract_addr, txhash_contract: txhash, authority_addr: authority}
  end

  def create_conf_file(%{contract_addr: contract_addr, txhash_contract: txhash, authority_addr: authority_addr}) do
    """
    use Mix.Config
    config :omg_eth,
      contract_addr: #{inspect(contract_addr)},
      txhash_contract: #{inspect(txhash)},
      authority_addr: #{inspect(authority_addr)}
    """
  end

  def create_and_fund_authority_addr do
    {:ok, authority} = Ethereumex.HttpClient.personal_new_account("")
    {:ok, _} = unlock_fund(authority)

    {:ok, authority}
  end

  @doc """
  Will take a map with eth-account information (from &generate_entity/0) and then
  import priv key->unlock->fund with lots of ether on that account
  """
  def import_unlock_fund(%{priv: account_priv, addr: account_addr} = _account) do
    account_priv_enc = Base.encode16(account_priv)
    {:ok, account_enc} = Crypto.encode_address(account_addr)

    {:ok, ^account_enc} = Ethereumex.HttpClient.personal_import_raw_key(account_priv_enc, "")
    {:ok, _} = unlock_fund(account_enc)

    {:ok, account_enc}
  end

  def make_deposits(value, accounts, contract \\ nil) do
    deposit = fn account ->
      {:ok, account_enc} = import_unlock_fund(account)

      {:ok, deposit_tx_hash} = OMG.Eth.RootChain.deposit(value, account_enc, contract)
      {:ok, receipt} = OMG.Eth.WaitFor.eth_receipt(deposit_tx_hash)
      deposit_blknum = OMG.Eth.RootChain.deposit_blknum_from_receipt(receipt)

      {:ok, account, deposit_blknum, value}
    end

    accounts
    |> Enum.map(&Task.async(fn -> deposit.(&1) end))
    |> Enum.map(fn task -> Task.await(task, :infinity) end)
  end

  # private

  defp unlock_fund(account_enc) do
    {:ok, true} = Ethereumex.HttpClient.personal_unlock_account(account_enc, "", 0)

    {:ok, [eth_source_address | _]} = Ethereumex.HttpClient.eth_accounts()
    txmap = %{from: eth_source_address, to: account_enc, value: encode_eth_rpc_unsigned_int(@one_hundred_eth)}
    {:ok, tx_fund} = Ethereumex.HttpClient.eth_send_transaction(txmap)
    WaitFor.eth_receipt(tx_fund, @about_4_blocks_time)
  end
end
