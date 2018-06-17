defmodule ExBankingTest do
  use ExUnit.Case
  doctest ExBanking

  setup context do
    start_supervised!({ExBanking.Supervisor, [registry: context.test]})
    Map.put(context, :opts, registry: context.test)
  end

  test "test global" do
    assert ExBanking.create_user("global_user") == :ok
    assert ExBanking.deposit("global_user", 20, "USD") == {:ok, 20.0}
    assert ExBanking.deposit("global_user", 0.02, "USD") == {:ok, 20.02}
    assert ExBanking.withdraw("global_user", 5.4, "USD") == {:ok, 14.62}
    assert ExBanking.get_balance("global_user", "USD") == {:ok, 14.62}
    assert ExBanking.get_balance("global_user", "EUR") == {:ok, 0.0}
    assert ExBanking.create_user("global_other_user") == :ok
    assert ExBanking.send("global_user", "global_other_user", 8.3, "USD") == {:ok, 6.32, 8.30}
  end

  test "create user", %{opts: opts} do
    assert ExBanking.create_user("local_user", opts) == :ok
    assert ExBanking.create_user("local_user", opts) == {:error, :user_already_exists}
    assert ExBanking.get_user("local_user", opts).name == "local_user"
    assert ExBanking.get_user("local_user") == {:error, :user_does_not_exist}
  end

  test "deposit", %{opts: opts} do
    ExBanking.create_user("user", opts)
    assert ExBanking.deposit("no_user", 10, "EUR", opts) == {:error, :user_does_not_exist}
    assert ExBanking.deposit("user", -10, "EUR", opts) == {:error, :wrong_arguments}
    assert ExBanking.deposit("user", 1.111, "EUR", opts) == {:error, :wrong_arguments}
    assert ExBanking.deposit("user", 10, "EUR", opts) === {:ok, 10.0}
    assert ExBanking.deposit("user", 10.22, "EUR", opts) === {:ok, 20.22}

    tasks = ExBanking.Tasks.make_busy("user", opts)
    assert ExBanking.deposit("user", 1.11, "EUR", opts) == {:error, :too_many_requests_to_user}
    ExBanking.Tasks.make_free("user", tasks, opts)
    assert ExBanking.deposit("user", 1.11, "EUR", opts) == {:ok, 21.33}
  end

  test "withdraw", %{opts: opts} do
    ExBanking.create_user("user", opts)
    assert ExBanking.deposit("no_user", 10, "EUR", opts) == {:error, :user_does_not_exist}
    assert ExBanking.deposit("user", -10, "EUR", opts) == {:error, :wrong_arguments}
    assert ExBanking.deposit("user", 4.551, "EUR", opts) == {:error, :wrong_arguments}
    assert ExBanking.deposit("user", 10, "EUR", opts) === {:ok, 10.0}
    assert ExBanking.withdraw("user", 5.5, "EUR", opts) === {:ok, 4.5}
    assert ExBanking.withdraw("user", 5.5, "EUR", opts) === {:error, :not_enough_money}

    tasks = ExBanking.Tasks.make_busy("user", opts)

    assert ExBanking.withdraw("user", 1.0, "EUR", opts) === {:error, :too_many_requests_to_user}

    ExBanking.Tasks.make_free("user", tasks, opts)
    assert ExBanking.withdraw("user", 1.0, "EUR", opts) === {:ok, 3.5}
  end

  test "get balance", %{opts: opts} do
    ExBanking.create_user("user", opts)
    assert ExBanking.get_balance("no_user", "EUR", opts) == {:error, :user_does_not_exist}
    assert ExBanking.get_balance("user", "EUR", opts) === {:ok, 0.0}
    assert ExBanking.deposit("user", 5.52, "EUR", opts) === {:ok, 5.52}
    assert ExBanking.get_balance("user", "EUR", opts) === {:ok, 5.52}

    tasks = ExBanking.Tasks.make_busy("user", opts)
    assert ExBanking.get_balance("user", "EUR", opts) === {:error, :too_many_requests_to_user}
    ExBanking.Tasks.make_free("user", tasks, opts)
    assert ExBanking.get_balance("user", "EUR", opts) === {:ok, 5.52}
  end

  test "send", %{opts: opts} do
    ExBanking.create_user("from_user", opts)
    ExBanking.create_user("to_user", opts)
    assert ExBanking.deposit("from_user", 10.54, "EUR", opts) == {:ok, 10.54}

    assert ExBanking.send("no_user", "to_user", 3.0, "EUR", opts) ===
             {:error, :sender_does_not_exist}

    assert ExBanking.send("from_user", "to_user", 12.0, "EUR", opts) ===
             {:error, :not_enough_money}

    assert ExBanking.send("from_user", "no_user", 3.0, "EUR", opts) ===
             {:error, :receiver_does_not_exist}

    assert ExBanking.send("from_user", "to_user", 3.0, "EUR", opts) === {:ok, 7.54, 3.0}
    assert ExBanking.get_balance("from_user", "EUR", opts) === {:ok, 7.54}
    assert ExBanking.get_balance("to_user", "EUR", opts) === {:ok, 3.0}

    tasks = ExBanking.Tasks.make_busy("from_user", opts)

    assert ExBanking.send("from_user", "to_user", 2.2, "EUR", opts) ===
             {:error, :too_many_requests_to_sender}

    ExBanking.Tasks.make_free("from_user", tasks, opts)
    tasks = ExBanking.Tasks.make_busy("to_user", opts)

    assert ExBanking.send("from_user", "to_user", 2.2, "EUR", opts) ===
             {:error, :too_many_requests_to_receiver}

    ExBanking.Tasks.make_free("to_user", tasks, opts)
    assert ExBanking.send("from_user", "to_user", 2.2, "EUR", opts) === {:ok, 5.34, 5.2}
  end

  test "other_registry" do
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

  test "get balance racing", %{opts: opts} do
    ExBanking.create_user("user", opts)
    assert ExBanking.deposit("user", 5.52, "EUR", opts) === {:ok, 5.52}
    assert ExBanking.get_balance("user", "EUR", opts) === {:ok, 5.52}

    tasks = ExBanking.Tasks.make_busy("user", opts)

    assert ExBanking.get_balance("user", "EUR", opts) === {:error, :too_many_requests_to_user}

    ExBanking.create_user("other_user", opts)
    assert ExBanking.get_balance("other_user", "EUR", opts) === {:ok, 0.0}
    ExBanking.Tasks.make_free("user", tasks, opts)
    assert ExBanking.get_balance("user", "EUR", opts) === {:ok, 5.52}
  end
end
