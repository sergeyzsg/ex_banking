defmodule ExBankingTest do
  use ExUnit.Case
  doctest ExBanking

  test "create get user" do
    assert ExBanking.create_user("vavah") == :ok
    assert ExBanking.create_user("vavah") == {:error, :user_already_exists}
    assert ExBanking.get_user("vavah").name == "vavah"
    assert ExBanking.get_name("vavah") == "vavah"
  end

  test "deposit" do
    ExBanking.create_user("deposit")
    assert ExBanking.deposit("no_user", 10, "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.deposit("deposit", -10, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("deposit", 1.111, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("deposit", 10, "EUR") === {:ok, 10.0}
    assert ExBanking.deposit("deposit", 10.22, "EUR") === {:ok, 20.22}
  end

  test "withdraw" do
    ExBanking.create_user("withdraw")
    assert ExBanking.deposit("no_user", 10, "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.deposit("withdraw", -10, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("withdraw", 4.551, "EUR") == {:error, :wrong_arguments}
    assert ExBanking.deposit("withdraw", 10, "EUR") === {:ok, 10.0}
    assert ExBanking.withdraw("withdraw", 5.5, "EUR") === {:ok, 4.5}
    assert ExBanking.withdraw("withdraw", 5.5, "EUR") === {:error, :not_enough_money}
  end

  test "get balance" do
    ExBanking.create_user("balance")
    assert ExBanking.get_balance("no_user", "EUR") == {:error, :user_does_not_exist}
    assert ExBanking.get_balance("balance", "EUR") === {:ok, 0.0}
    assert ExBanking.deposit("balance", 5.52, "EUR") === {:ok, 5.52}
    assert ExBanking.get_balance("balance", "EUR") === {:ok, 5.52}
  end
end
