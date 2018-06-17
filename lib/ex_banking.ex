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
  def deposit(user, amount, currency) do
    case validate_amount(amount) do
      {:error, descr} -> {:error, descr}
      valid_amount -> call_user_server(user, {:deposit, [valid_amount, currency]})
    end
  end

  @spec withdraw(user :: String.t(), amount :: number, currency :: String.t()) ::
          {:ok, new_balance :: number} | banking_error
  def withdraw(user, amount, currency) do
    case validate_amount(amount) do
      {:error, descr} -> {:error, descr}
      valid_amount -> call_user_server(user, {:withdraw, [valid_amount, currency]})
    end
  end

  @spec get_balance(user :: String.t(), currency :: String.t()) ::
          {:ok, balance :: number} | banking_error
  def get_balance(user, currency) do
    call_user_server(user, {:get_balance, [currency]})
  end

  @spec send(
          from_user :: String.t(),
          to_user :: String.t(),
          amount :: number,
          currency :: String.t()
        ) :: {:ok, from_user_balance :: number, to_user_balance :: number} | banking_error
  def send(from_user, to_user, amount, currency) do
    result =
      case validate_amount(amount) do
        {:error, descr} -> {:error, descr}
        valid_amount -> call_user_server(from_user, {:send, [to_user, valid_amount, currency]})
      end

    case result do
      {:error, :user_does_not_exist} -> {:error, :sender_does_not_exist}
      {:error, :too_many_requests_to_user} -> {:error, :too_many_requests_to_sender}
      rr -> rr
    end
  end

  def call_user_server(username, request, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case UserRegistry.get_user_worker(username, registry) do
      {:ok, pid} -> GenServer.call(pid, request)
      error -> error
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
    defstruct name: nil, balance: %{}, task_count: 0, holds: %{}, trans_hist: []
  end

  defmodule UserWorker do
    use GenServer

    @impl true
    def init(user) do
      {:ok, user}
    end

    def task_deposit(server, _user, amount, currency) do
      GenServer.call(server, {:increase, amount, currency})
    end

    def task_withdraw(server, _user, amount, currency) do
      GenServer.call(server, {:decreace, amount, currency})
    end

    def task_get_balance(_server, user, currency) do
      {:ok, Map.get(user.balance, currency, 0.0)}
    end

    def task_send(server, _user, to_user, amount, currency) do
      case GenServer.call(server, {:hold, amount, currency}) do
        {:error, descr} ->
          {:error, descr}

        {:ok, hold_uuid} ->
          case ExBanking.call_user_server(
                 to_user,
                 {:trans_deposit, [hold_uuid, amount, currency]}
               ) do
            {:ok, to_user_balance} ->
              {:ok, from_user_balance} = GenServer.call(server, {:clear, hold_uuid})
              {:ok, from_user_balance, to_user_balance}

            {:error, err} ->
              GenServer.call(server, {:unhold, hold_uuid})

              case err do
                :user_does_not_exist -> {:error, :receiver_does_not_exist}
                :too_many_requests_to_user -> {:error, :too_many_requests_to_receiver}
                _ -> {:error, err}
              end
          end
      end
    end

    def task_trans_deposit(server, _user, hold_uuid, amount, currency) do
      GenServer.call(server, {:trans_increase, hold_uuid, amount, currency})
    end

    @impl true
    def handle_cast(:done, user) do
      {:noreply, %{user | task_count: user.task_count - 1}}
    end

    @impl true
    def handle_call({:increase, amount, currency}, _from, user) do
      new_balance = increase_balance(user.balance, amount, currency)
      {:reply, {:ok, new_balance[currency]}, %{user | balance: new_balance}}
    end

    @impl true
    def handle_call({:trans_increase, hold_uuid, amount, currency}, _from, user) do
      new_balance = increase_balance(user.balance, amount, currency)

      new_user = %{
        user
        | balance: new_balance,
          trans_hist: [{hold_uuid, amount, currency} | user.trans_hist]
      }

      {:reply, {:ok, new_balance[currency]}, new_user}
    end

    @impl true
    def handle_call({:decreace, amount, currency}, _from, user) do
      new_balance = decrease_balance(user.balance, amount, currency)

      if new_balance[currency] < 0 do
        {:reply, {:error, :not_enough_money}, user}
      else
        {:reply, {:ok, new_balance[currency]}, %{user | balance: new_balance}}
      end
    end

    @impl true
    def handle_call({:hold, amount, currency}, _from, user) do
      new_balance = decrease_balance(user.balance, amount, currency)

      if new_balance[currency] < 0 do
        {:reply, {:error, :not_enough_money}, user}
      else
        hold_uuid = {DateTime.utc_now(), :rand.uniform()}

        new_user = %{
          user
          | balance: new_balance,
            holds: Map.put(user.holds, hold_uuid, {amount, currency})
        }

        {:reply, {:ok, hold_uuid}, new_user}
      end
    end

    @impl true
    def handle_call({:clear, hold_uuid}, _from, user) do
      {_amount, currency} = user.holds[hold_uuid]
      new_user = %{user | holds: Map.delete(user.holds, hold_uuid)}
      {:reply, {:ok, Map.get(user.balance, currency, 0.0)}, new_user}
    end

    @impl true
    def handle_call({:unhold, hold_uuid}, _from, user) do
      {amount, currency} = user.holds[hold_uuid]
      new_balance = increase_balance(user.balance, amount, currency)
      new_user = %{user | balance: new_balance, holds: Map.delete(user.holds, hold_uuid)}
      {:reply, {:ok, Map.get(new_balance, currency, 0.0)}, new_user}
    end

    @impl true
    def handle_call({operation, args}, from, user)
        when operation in [:deposit, :withdraw, :get_balance, :send, :trans_deposit] do
      if user.task_count >= 10 do
        {:reply, {:error, :too_many_requests_to_user}, user}
      else
        server = self()

        Task.start_link(fn ->
          result = apply(UserWorker, String.to_atom("task_#{operation}"), [server, user] ++ args)
          GenServer.reply(from, result)
          GenServer.cast(server, :done)
        end)

        {:noreply, %{user | task_count: user.task_count + 1}}
      end
    end

    @impl true
    def handle_call(:get, _from, user) do
      {:reply, user, user}
    end

    @impl true
    def handle_call(:make_busy, _from, user) do
      {:reply, :ok, %{user | task_count: user.task_count + 10}}
    end

    @impl true
    def handle_call(:make_free, _from, user) do
      {:reply, :ok, %{user | task_count: user.task_count - 10}}
    end

    defp increase_balance(balance, amount, currency) do
      Map.put(balance, currency, Float.round(Map.get(balance, currency, 0.0) + amount, 2))
    end

    defp decrease_balance(balance, amount, currency) do
      Map.put(balance, currency, Float.round(Map.get(balance, currency, 0.0) - amount, 2))
    end
  end

  # UserWorker

  def create_user_server(user_name) do
    user = %User{name: user_name}
    {:ok, worker} = GenServer.start_link(UserWorker, user)
    worker
  end

  def get_user(username, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)

    case UserRegistry.get_user_worker(username, registry) do
      {:ok, pid} -> GenServer.call(pid, :get)
      error -> error
    end
  end

  def make_busy(username, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)
    {:ok, pid} = UserRegistry.get_user_worker(username, registry)
    GenServer.call(pid, :make_busy)
  end

  def make_free(username, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)
    {:ok, pid} = UserRegistry.get_user_worker(username, registry)
    GenServer.call(pid, :make_free)
  end
end
