defmodule ExBanking.Supervisor do
  use Supervisor

  def start_link(registry: registry) do
    supervisor_name = Module.concat(registry, ExBanking.Supervisor)

    Supervisor.start_link(__MODULE__, [registry: registry], name: supervisor_name)
  end

  def init(registry: registry) do
    children = [
      {ExBanking.UserRegistry,
       [name: Module.concat(registry, ExBanking.UserRegistry), registry: registry]},
      {ExBanking.UserHolderSupervisor,
       [name: Module.concat(registry, ExBanking.UserHolderSupervisor)]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule ExBanking.UserHolderSupervisor do
  use DynamicSupervisor

  def start_link(name: name) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: name)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def create_balance_holder(user_name, registry) do
    supervisor = Module.concat(registry, ExBanking.UserHolderSupervisor)
    user = %ExBanking.User{name: user_name}

    {:ok, user_supervisor} =
      DynamicSupervisor.start_child(supervisor, %{
        id: {registry, user_name},
        start: {Supervisor, :start_link, [[], [strategy: :one_for_all]]}
      })

    {:ok, holder} = Supervisor.start_child(user_supervisor, {ExBanking.UserHolder, user})

    {:ok, task_supervisor} =
      Supervisor.start_child(
        user_supervisor,
        {Task.Supervisor, [max_children: 10]}
      )

    {:ok, holder, task_supervisor}
  end
end
