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

defmodule OMG.Watcher.TransactionDBTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.API.Fixtures
  use Plug.Test

  alias OMG.API.Block
  alias OMG.API.Crypto
  alias OMG.API.State.Transaction.{Recovered, Signed}
  alias OMG.API.Utxo
  alias OMG.Watcher.TransactionDB

  require Utxo

  @eth Crypto.zero_address()

  describe "Transaction database" do
    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob]
    test "insert and retrive transaction", %{alice: alice, bob: bob} do
      tester_f = fn {blknum, txindex, recovered_tx} ->
        [{:ok, %TransactionDB{txhash: id}}] = TransactionDB.update_with(%Block{transactions: [recovered_tx], number: blknum})
        expected_transaction = create_expected_transaction(id, recovered_tx, blknum, txindex)
        assert expected_transaction == delete_meta(TransactionDB.get(id))
      end

      [
        {0, 0, OMG.API.TestHelper.create_recovered([], @eth, [{alice, 100}])},
        {0, 1, OMG.API.TestHelper.create_recovered([{2, 3, 1, bob}], @eth, [{alice, 200}])},
        {0, 2, OMG.API.TestHelper.create_recovered([{2, 3, 1, bob}, {2, 3, 1, alice}], @eth, [{alice, 200}])},
        {0, 3, OMG.API.TestHelper.create_recovered([{2, 3, 1, bob}], @eth, [{alice, 200}, {bob, 200}])},
        {1000, 0, OMG.API.TestHelper.create_recovered([{2, 3, 2, bob}, {2, 3, 1, alice}], @eth, [{alice, 200}])}
      ]
      |> Enum.map(tester_f)
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob]
    test "insert and retrive block of transactions ", %{alice: alice, bob: bob} do
      blknum = 0
      recovered_tx1 = OMG.API.TestHelper.create_recovered([{2, 3, 1, bob}], @eth, [{alice, 200}])
      recovered_tx2 = OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 100}])

      [{:ok, %TransactionDB{txhash: txhash_1}}, {:ok, %TransactionDB{txhash: txhash_2}}] =
        TransactionDB.update_with(%Block{
          transactions: [
            recovered_tx1,
            recovered_tx2
          ],
          number: blknum
        })

      assert create_expected_transaction(txhash_1, recovered_tx1, blknum, 0) == delete_meta(TransactionDB.get(txhash_1))
      assert create_expected_transaction(txhash_2, recovered_tx2, blknum, 1) == delete_meta(TransactionDB.get(txhash_2))
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob]
    test "gets all transactions from a block", %{alice: alice, bob: bob} do
      blknum = 1000
      assert [] == TransactionDB.get_by_blknum(blknum)

      alice_spend_recovered = OMG.API.TestHelper.create_recovered([], @eth, [{alice, 100}])
      bob_spend_recovered = OMG.API.TestHelper.create_recovered([], @eth, [{bob, 200}])

      [{:ok, %TransactionDB{txhash: txhash_alice}}, {:ok, %TransactionDB{txhash: txhash_bob}}] =
        TransactionDB.update_with(%Block{
          transactions: [alice_spend_recovered, bob_spend_recovered],
          number: blknum
        })

      assert [
               create_expected_transaction(txhash_alice, alice_spend_recovered, blknum, 0),
               create_expected_transaction(txhash_bob, bob_spend_recovered, blknum, 1)
             ] == blknum |> TransactionDB.get_by_blknum() |> Enum.map(&delete_meta/1)
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob]
    test "gets transaction that spends utxo", %{alice: alice, bob: bob} do
      utxo1 = Utxo.position(1000, 0, 0)
      utxo2 = Utxo.position(2000, 0, 0)
      {:error, :utxo_not_spent} = TransactionDB.get_transaction_challenging_utxo(utxo1)
      {:error, :utxo_not_spent} = TransactionDB.get_transaction_challenging_utxo(utxo2)

      alice_spend_recovered = OMG.API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 100}])

      [{:ok, %TransactionDB{txhash: txhash_alice}}] =
        TransactionDB.update_with(%Block{
          transactions: [alice_spend_recovered],
          number: 1000
        })

      assert create_expected_transaction(txhash_alice, alice_spend_recovered, 1, 0) ==
               delete_meta(TransactionDB.get_transaction_challenging_utxo(utxo1))

      {:error, :utxo_not_spent} = TransactionDB.get_transaction_challenging_utxo(utxo2)

      bob_spend_recovered = OMG.API.TestHelper.create_recovered([{2, 0, 0, bob}], @eth, [{alice, 100}])

      [{:ok, %TransactionDB{txhash: txhash_bob}}] =
        TransactionDB.update_with(%Block{
          transactions: [bob_spend_recovered],
          number: 2000
        })

      assert create_expected_transaction(txhash_bob, bob_spend_recovered, 2, 0) ==
               delete_meta(TransactionDB.get_transaction_challenging_utxo(utxo2))
    end

    defp create_expected_transaction(
           txhash,
           %Recovered{
             signed_tx: %Signed{raw_tx: transaction, sig1: sig1, sig2: sig2} = signed_tx,
             spender1: spender1,
             spender2: spender2
           },
           blknum,
           txindex
         ) do
      %TransactionDB{
        blknum: blknum,
        txindex: txindex,
        txhash: txhash,
        txbytes: Signed.encode(signed_tx)
      }
      |> delete_meta
    end

    defp delete_meta(%TransactionDB{} = transaction) do
      Map.delete(transaction, :__meta__)
    end

    defp delete_meta({:ok, %TransactionDB{} = transaction}) do
      delete_meta(transaction)
    end
  end
end
