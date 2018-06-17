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

  def get_balance_worker(user_holder, currency) do
    ExBanking.UserHolder.get_balance(user_holder, currency)
  end

  def deposit_worker(user_holder, amount, currency) do
    ExBanking.UserHolder.deposit(user_holder, amount, currency)
  end

  def withdraw_worker(user_holder, amount, currency) do
    ExBanking.UserHolder.withdraw(user_holder, amount, currency)
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

  def make_busy(user, registry, number \\ 10) do
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

  def make_free(user, registry, tasks) do
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
