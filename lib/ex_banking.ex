defmodule ExBanking do
  @moduledoc """
  Documentation for ExBanking.
  """
  use Application
  alias ExBanking.UserRegistry, as: UserRegistry

  def start(_type, _args) do
    ExBanking.Supervisor.start_link(registry: ExBanking)
  end

  @type banking_error ::
          {:error,
           :wrong_arguments
           | :user_already_exists
           | :user_does_not_exist
           | :not_enough_money
           | :sender_does_not_exist
           | :receiver_does_not_exist
           | :too_many_requests_to_user
           | :too_many_requests_to_sender
           | :too_many_requests_to_receiver}

  @spec create_user(user :: String.t()) :: :ok | banking_error
  def create_user(user, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)
    UserRegistry.create_user(user, registry)
  end

  @spec deposit(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number} | banking_error
  def deposit(user, amount, currency, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case validate_amount(amount) do
      {:error, descr} -> {:error, descr}
      valid_amount -> ExBanking.Tasks.deposit(user, valid_amount, currency, registry)
    end
  end

  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case validate_amount(amount) do
      {:error, descr} -> {:error, descr}
      valid_amount -> ExBanking.Tasks.withdraw(user, valid_amount, currency, registry)
    end
  end

  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number} | banking_error
  def get_balance(user, currency, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)
    ExBanking.Tasks.get_balance(user, currency, registry)
  end

  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(from_user, to_user, amount, currency, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case validate_amount(amount) do
      {:error, descr} -> {:error, descr}
      valid_amount -> ExBanking.Tasks.send(from_user, to_user, valid_amount, currency, registry)
    end
  end

  defp validate_amount(amount) do
    rounded_amount = Float.round(amount / 1, 2)

    if rounded_amount <= 0 or rounded_amount != amount do
      {:error, :wrong_arguments}
    else
      rounded_amount
    end
  end

  defmodule User do
    defstruct name: nil, balance: %{}, holds: %{}, trans_hist: []
  end

  def get_user(username, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case UserRegistry.get_user_holder(username, registry) do
      {:ok, pid} -> GenServer.call(pid, :get)
      error -> error
    end
  end
end
