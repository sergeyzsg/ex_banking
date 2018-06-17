defmodule ExBanking.Tasks do
  def get_balance(user, currency, registry) do
    case ExBanking.UserRegistry.get_processes(user, registry) do
      {:ok, {user_holder, task_supervisor}} ->
        run_task(:get_balance_worker, [user_holder, currency], task_supervisor)

      error ->
        error
    end
  end

  def deposit(user, amount, currency, registry) do
    case ExBanking.UserRegistry.get_processes(user, registry) do
      {:ok, {user_holder, task_supervisor}} ->
        run_task(:deposit_worker, [user_holder, amount, currency], task_supervisor)

      error ->
        error
    end
  end

  def withdraw(user, amount, currency, registry) do
    case ExBanking.UserRegistry.get_processes(user, registry) do
      {:ok, {user_holder, task_supervisor}} ->
        run_task(:withdraw_worker, [user_holder, amount, currency], task_supervisor)

      error ->
        error
    end
  end

  def send(user, to_user, amount, currency, registry) do
    result =
      case ExBanking.UserRegistry.get_processes(user, registry) do
        {:ok, {user_holder, task_supervisor}} ->
          run_task(
            :send_worker,
            [user_holder, to_user, amount, currency, registry],
            task_supervisor
          )

        error ->
          error
      end

    case result do
      {:error, :user_does_not_exist} -> {:error, :sender_does_not_exist}
      {:error, :too_many_requests_to_user} -> {:error, :too_many_requests_to_sender}
      error -> error
    end
  end

  def trans_deposit(user, hold_uuid, amount, currency, registry) do
    case ExBanking.UserRegistry.get_processes(user, registry) do
      {:ok, {user_holder, task_supervisor}} ->
        run_task(
          :trans_deposit_worker,
          [user_holder, hold_uuid, amount, currency],
          task_supervisor
        )

      error ->
        error
    end
  end

  def get_balance_worker(user_holder, currency) do
    ExBanking.UserHolder.get_balance(user_holder, currency)
  end

  def deposit_worker(user_holder, amount, currency) do
    ExBanking.UserHolder.deposit(user_holder, amount, currency)
  end

  def withdraw_worker(user_holder, amount, currency) do
    ExBanking.UserHolder.withdraw(user_holder, amount, currency)
  end

  # TODO: restoration if send failed
  def send_worker(user_holder, to_user, amount, currency, registry) do
    case ExBanking.UserHolder.hold(user_holder, to_user, amount, currency) do
      {:error, descr} ->
        {:error, descr}

      {:ok, hold_uuid} ->
        send_worker_2_step(user_holder, hold_uuid, to_user, amount, currency, registry)
    end
  end

  defp send_worker_2_step(user_holder, hold_uuid, to_user, amount, currency, registry) do
    case trans_deposit(to_user, hold_uuid, amount, currency, registry) do
      {:ok, to_user_balance} ->
        {:ok, from_user_balance} = ExBanking.UserHolder.clear(user_holder, hold_uuid)
        {:ok, from_user_balance, to_user_balance}

      {:error, err} ->
        {:ok, _b} = ExBanking.UserHolder.unhold(user_holder, hold_uuid)

        case err do
          :user_does_not_exist -> {:error, :receiver_does_not_exist}
          :too_many_requests_to_user -> {:error, :too_many_requests_to_receiver}
          _ -> {:error, err}
        end
    end
  end

  def trans_deposit_worker(user_holder, hold_uuid, amount, currency) do
    ExBanking.UserHolder.trans_deposit(user_holder, hold_uuid, amount, currency)
  end

  defp run_task(func, args, supervisor) do
    try do
      Task.Supervisor.async(supervisor, __MODULE__, func, args)
    rescue
      # async generate error (MatchError) no match of right hand side value: {:error, :max_children}
      MatchError ->
        {:error, :too_many_requests_to_user}
    else
      task -> Task.await(task)
    end
  end

  def make_busy(user, opts \\ []) do
    registry = Keyword.get(opts, :registry, ExBanking)
    number = Keyword.get(opts, :number, 10)
    {:ok, supervisor} = ExBanking.UserRegistry.get_user_task_supervisor(user, registry)
    make_busy_r(number, supervisor)
  end

  defp make_busy_r(number, _supervisor) when number <= 0 do
    []
  end

  defp make_busy_r(number, supervisor) do
    task = Task.Supervisor.async_nolink(supervisor, __MODULE__, :infinity, [])
    [task | make_busy_r(number - 1, supervisor)]
  end

  def infinity() do
    Process.sleep(5000)
    infinity()
  end

  def make_free(user, tasks, opts) do
    registry = Keyword.get(opts, :registry, ExBanking)
    {:ok, supervisor} = ExBanking.UserRegistry.get_user_task_supervisor(user, registry)
    make_free_r(supervisor, tasks)
  end

  defp make_free_r(_supervisor, []) do
  end

  defp make_free_r(supervisor, [task | tail]) do
    Task.Supervisor.terminate_child(supervisor, task.pid)
    make_free_r(supervisor, tail)
  end
end
