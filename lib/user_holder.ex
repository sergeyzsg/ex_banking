defmodule ExBanking.UserHolder do
  use GenServer, restart: :temporary

  def start_link(user) do
    GenServer.start_link(__MODULE__, user)
  end

  @impl true
  def init(user) do
    {:ok, user}
  end

  def get_balance(user_holder, currency) do
    GenServer.call(user_holder, {:get_balance_call, currency})
  end

  def deposit(user_holder, amount, currency) do
    GenServer.call(user_holder, {:increase, amount, currency})
  end

  def withdraw(user_holder, amount, currency) do
    GenServer.call(user_holder, {:decreace, amount, currency})
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
  def handle_call(msg, from, state) do
    try do
      handle_call_real(msg, from, state)
    rescue
      error -> {:error, error}
    end
  end

  defp handle_call_real({:get_balance_call, currency}, _from, user) do
    {:reply, {:ok, Map.get(user.balance, currency, 0.0)}, user}
  end

  defp handle_call_real({:increase, amount, currency}, _from, user) do
    new_balance = increase_balance(user.balance, amount, currency)
    {:reply, {:ok, new_balance[currency]}, %{user | balance: new_balance}}
  end

  defp handle_call_real({:decreace, amount, currency}, _from, user) do
    new_balance = decrease_balance(user.balance, amount, currency)

    if new_balance[currency] < 0 do
      {:reply, {:error, :not_enough_money}, user}
    else
      {:reply, {:ok, new_balance[currency]}, %{user | balance: new_balance}}
    end
  end

  defp handle_call_real({:trans_increase, hold_uuid, amount, currency}, _from, user) do
    new_balance = increase_balance(user.balance, amount, currency)

    new_user = %{
      user
      | balance: new_balance,
        trans_hist: [{hold_uuid, amount, currency} | user.trans_hist]
    }

    {:reply, {:ok, new_balance[currency]}, new_user}
  end

  defp handle_call_real({:hold, amount, currency}, _from, user) do
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

  defp handle_call_real({:clear, hold_uuid}, _from, user) do
    {_amount, currency} = user.holds[hold_uuid]
    new_user = %{user | holds: Map.delete(user.holds, hold_uuid)}
    {:reply, {:ok, Map.get(user.balance, currency, 0.0)}, new_user}
  end

  defp handle_call_real({:unhold, hold_uuid}, _from, user) do
    {amount, currency} = user.holds[hold_uuid]
    new_balance = increase_balance(user.balance, amount, currency)
    new_user = %{user | balance: new_balance, holds: Map.delete(user.holds, hold_uuid)}
    {:reply, {:ok, Map.get(new_balance, currency, 0.0)}, new_user}
  end

  defp handle_call_real({operation, args}, from, user)
       when operation in [:send, :trans_deposit] do
    if user.task_count >= 10 do
      {:reply, {:error, :too_many_requests_to_user}, user}
    else
      server = self()

      Task.start_link(fn ->
        result = apply(__MODULE__, String.to_atom("task_#{operation}"), [server, user] ++ args)
        GenServer.reply(from, result)
        GenServer.cast(server, :done)
      end)

      {:noreply, %{user | task_count: user.task_count + 1}}
    end
  end

  defp handle_call_real(:get, _from, user) do
    {:reply, user, user}
  end

  defp handle_call_real(:make_busy, _from, user) do
    {:reply, :ok, %{user | task_count: user.task_count + 10}}
  end

  defp handle_call_real(:make_free, _from, user) do
    {:reply, :ok, %{user | task_count: user.task_count - 10}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp increase_balance(balance, amount, currency) do
    Map.put(balance, currency, Float.round(Map.get(balance, currency, 0.0) + amount, 2))
  end

  defp decrease_balance(balance, amount, currency) do
    Map.put(balance, currency, Float.round(Map.get(balance, currency, 0.0) - amount, 2))
  end
end
