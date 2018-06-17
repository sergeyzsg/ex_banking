defmodule ExBankingTest do
  use ExUnit.Case
  doctest ExBanking

  setup context do
    start_supervised!({ExBanking.Supervisor, [registry: context.test]})
    Map.put(context, :opts, registry: context.test)
  end

  test "create global user" do
    assert ExBanking.create_user("vavah_user") == :ok
    assert ExBanking.create_user("vavah_user") == {:error, :user_already_exists}
    assert ExBanking.get_user("vavah_user").name == "vavah_user"
  end

  test "create local user", context do
    assert ExBanking.create_user("local_user", context.opts) == :ok
    assert ExBanking.create_user("local_user", context.opts) == {:error, :user_already_exists}
    assert ExBanking.get_user("local_user", context.opts).name == "local_user"
    assert ExBanking.get_user("local_user") == {:error, :user_does_not_exist}
  end

  test "deposit" do
    ExBanking.create_user("deposit_user")
    assert ExBanking.deposit("no_user", 10, "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.deposit("deposit_user", -10, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("deposit_user", 1.111, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("deposit_user", 10, "EUR") === {:ok, 10.0}
    assert ExBanking.deposit("deposit_user", 10.22, "EUR") === {:ok, 20.22}

    ExBanking.make_busy("deposit_user")
    assert ExBanking.deposit("deposit_user", 1.11, "EUR") == {:error, :too_many_requests_to_user}
    ExBanking.make_free("deposit_user")
    assert ExBanking.deposit("deposit_user", 1.11, "EUR") == {:ok, 21.33}
  end

  test "withdraw" do
    ExBanking.create_user("withdraw_user")
    assert ExBanking.deposit("no_user", 10, "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.deposit("withdraw_user", -10, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("withdraw_user", 4.551, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("withdraw_user", 10, "EUR") === {:ok, 10.0}
    assert ExBanking.withdraw("withdraw_user", 5.5, "EUR") === {:ok, 4.5}
    assert ExBanking.withdraw("withdraw_user", 5.5, "EUR") === {:error, :not_enough_money}

    ExBanking.make_busy("withdraw_user")

    assert ExBanking.withdraw("withdraw_user", 1.0, "EUR") ===
             {:error, :too_many_requests_to_user}

    ExBanking.make_free("withdraw_user")
    assert ExBanking.withdraw("withdraw_user", 1.0, "EUR") === {:ok, 3.5}
  end

  test "get balance" do
    ExBanking.create_user("balance_user")
    assert ExBanking.get_balance("no_user", "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.get_balance("balance_user", "EUR") === {:ok, 0.0}
    assert ExBanking.deposit("balance_user", 5.52, "EUR") === {:ok, 5.52}
    assert ExBanking.get_balance("balance_user", "EUR") === {:ok, 5.52}

    tasks = ExBanking.Tasks.make_busy("balance_user", ExBanking)
    assert ExBanking.get_balance("balance_user", "EUR") === {:error, :too_many_requests_to_user}
    ExBanking.Tasks.make_free("balance_user", ExBanking, tasks)
    assert ExBanking.get_balance("balance_user", "EUR") === {:ok, 5.52}
  end

  test "send" do
    ExBanking.create_user("from_user")
    ExBanking.create_user("to_user")
    assert ExBanking.deposit("from_user", 10.54, "EUR") == {:ok, 10.54}
    assert ExBanking.send("no_user", "to_user", 3.0, "EUR") === {:error, :sender_does_not_exist}
    assert ExBanking.send("from_user", "to_user", 12.0, "EUR") === {:error, :not_enough_money}

    assert ExBanking.send("from_user", "no_user", 3.0, "EUR") ===
             {:error, :receiver_does_not_exist}

    assert ExBanking.send("from_user", "to_user", 3.0, "EUR") === {:ok, 7.54, 3.0}
    assert ExBanking.get_balance("from_user", "EUR") === {:ok, 7.54}
    assert ExBanking.get_balance("to_user", "EUR") === {:ok, 3.0}

    ExBanking.make_busy("from_user")

    assert ExBanking.send("from_user", "to_user", 2.2, "EUR") ===
             {:error, :too_many_requests_to_sender}

    ExBanking.make_free("from_user")
    ExBanking.make_busy("to_user")

    assert ExBanking.send("from_user", "to_user", 2.2, "EUR") ===
             {:error, :too_many_requests_to_receiver}

    ExBanking.make_free("to_user")
    assert ExBanking.send("from_user", "to_user", 2.2, "EUR") === {:ok, 5.34, 5.2}
  end

  test "other_name" do
    opts = [registry: :test_registry]
    {:ok, sv} = ExBanking.Supervisor.start_link(opts)
    assert ExBanking.create_user("tst_in_tst", opts) == :ok
    assert ExBanking.get_user("tst_in_tst", opts).name == "tst_in_tst"
    assert ExBanking.get_user("tst_in_tst") == {:error, :user_does_not_exist}
    Supervisor.stop(sv)

    {:ok, sv} = ExBanking.Supervisor.start_link(opts)
    assert ExBanking.get_user("tst_in_tst", opts) == {:error, :user_does_not_exist}
    assert ExBanking.create_user("tst_in_tst", opts) == :ok
    assert ExBanking.get_user("tst_in_tst", opts).name == "tst_in_tst"
    Supervisor.stop(sv)
  end
end
