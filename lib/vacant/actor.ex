defmodule Vacant.Actor do
  @moduledoc """
  An actor that holds resources and searches for upgrades.

  Actors periodically evaluate their satisfaction with their current resource.
  When dissatisfied (or resourceless), they search for vacant resources and
  attempt to acquire the best one.
  """
  use GenServer

  def start_link(attr) do
    GenServer.start_link(
      __MODULE__,
      attr
    )
  end

  # Public API
  def init(%{
        utility_fn: utility_fn,
        satisfaction_fn: satisfaction_fn,
        interval: interval,
        exit_probability: exit_probability
      }) do
    schedule_tick(interval)

    {:ok,
     %{
       current_resource: nil,
       utility_fn: utility_fn,
       satisfaction_fn: satisfaction_fn,
       interval: interval,
       exit_probability: exit_probability
     }}
  end

  # Main loop
  def handle_info(:tick, state) do
    if should_exit?(state.exit_probability) do
      exit_market(state)
      {:stop, :exited, state}
    else
      new_state =
        state
        |> incr_tick_count()
        |> maybe_search()

      schedule_tick(new_state.interval)
      {:noreply, new_state}
    end
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end

  # Exit behavior

  defp should_exit?(probability), do: :rand.uniform() < probability

  defp exit_market(%{current_resource: nil}), do: :ok

  defp exit_market(%{current_resource: %{pid: pid}}) do
    Vacant.Resource.vacate(pid)
  end

  # Dwell time tracking

  defp incr_tick_count(%{current_resource: nil} = state), do: state

  defp incr_tick_count(%{current_resource: res} = state) do
    %{state | current_resource: %{res | ticks: res.ticks + 1}}
  end

  # Search and acquisition

  defp maybe_search(
         %{current_resource: res, satisfaction_fn: sat_fn, utility_fn: util_fn} = state
       ) do
    if should_search?(res, sat_fn) do
      search_and_acquire(util_fn, state)
    else
      state
    end
  end

  defp should_search?(nil, _sat_fn), do: true

  defp should_search?(%{attrs: attrs, ticks: ticks}, sat_fn) do
    sat_fn.(attrs, ticks) < 0
  end

  defp search_and_acquire(utility_fn, state) do
    case find_best_vacancy(utility_fn) do
      nil -> state
      pid -> try_acquire(pid, state)
    end
  end

  defp find_best_vacancy(utility_fn) do
    case :ets.match_object(:listings, {:_, :_, :vacant}) do
      [] -> nil
      vacancies -> select_best(vacancies, utility_fn)
    end
  end

  defp select_best(vacancies, utility_fn) do
    {pid, _attrs, :vacant} =
      Enum.max_by(vacancies, fn {_pid, attrs, _} -> utility_fn.(attrs) end)

    pid
  end

  defp try_acquire(pid, state) do
    case Vacant.Resource.occupy(pid) do
      {:ok, :acquired} -> acquire_success(pid, state)
      {:error, :already_occupied} -> state
    end
  end

  defp acquire_success(pid, state) do
    # If actor already has a resource, need to release it first!
    release_current(state.current_resource)

    attrs = get_resource_attrs(pid)
    %{state | current_resource: %{pid: pid, ticks: 0, attrs: attrs}}
  end

  defp release_current(nil), do: :ok
  defp release_current(%{pid: pid}), do: Vacant.Resource.vacate(pid)

  defp get_resource_attrs(pid) do
    case Vacant.Resource.status(pid) do
      %{attributes: attrs} -> attrs
      _ -> %{}
    end
  end
end
