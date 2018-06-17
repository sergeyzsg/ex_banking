defmodule ExBanking.UserRegistry do
  use GenServer, restart: :temporary

  def start_link(name: name, registry: registry) do
    GenServer.start_link(__MODULE__, [registry: registry], name: name)
  end

  def create_user(user_name, registry) do
    case :ets.lookup(registry, user_name) do
      [] ->
        GenServer.call(Module.concat(registry, __MODULE__), {:create_user, user_name})

      _ ->
        {:error, :user_already_exists}
    end
  end

  def get_processes(user_name, registry) do
    case :ets.lookup(registry, user_name) do
      [] -> {:error, :user_does_not_exist}
      [{_un, {holder, task_supervisor}}] -> {:ok, {holder, task_supervisor}}
    end
  end

  def get_user_holder(user_name, registry) do
    case :ets.lookup(registry, user_name) do
      [] -> {:error, :user_does_not_exist}
      [{_un, {holder, _task_supervisor}}] -> {:ok, holder}
    end
  end

  def get_user_task_supervisor(user_name, registry) do
    case :ets.lookup(registry, user_name) do
      [] -> {:error, :user_does_not_exist}
      [{_un, {_holder, task_supervisor}}] -> {:ok, task_supervisor}
    end
  end

  @impl true
  def init(registry: registry) do
    :ets.new(registry, [
      :set,
      :protected,
      {:write_concurrency, false},
      {:read_concurrency, true},
      :named_table
    ])

    {:ok, registry}
  end

  @impl true
  def handle_call(msg, from, state) do
    try do
      handle_call_real(msg, from, state)
    rescue
      error -> {:error, error}
    end
  end

  defp handle_call_real({:create_user, user_name}, _from, registry) do
    {:ok, holder, task_supervisor} =
      ExBanking.UserHolderSupervisor.create_balance_holder(user_name, registry)

    :ets.insert_new(registry, {user_name, {holder, task_supervisor}})
    {:reply, :ok, registry}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
