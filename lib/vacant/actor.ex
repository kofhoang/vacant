defmodule Vacant.Actor do
  @moduledoc """
  An actor that holds resources and searches for upgrades.

  Actors periodically evaluate their satisfaction with their current resource.
  When dissatisfied (or resourceless), they search for vacant resources and
  attempt to acquire the best one.
  """

  # Types

  @type satisfaction_fn :: (attrs :: map(), ticks :: non_neg_integer() -> float())
  @type utility_fn :: (attrs :: map() -> float())
  @type current_resource :: %{pid: pid(), ticks: non_neg_integer(), attrs: map()} | nil

  @type state :: %{
          current_resource: current_resource(),
          interval: pos_integer(),
          satisfaction_fn: satisfaction_fn(),
          utility_fn: utility_fn()
        }

  @exit_probability 0.01

  # Public API

  @spec start(utility_fn(), satisfaction_fn(), pos_integer()) :: pid()
  def start(utility_fn, satisfaction_fn, interval) do
    spawn(fn ->
      state = %{
        current_resource: nil,
        utility_fn: utility_fn,
        satisfaction_fn: satisfaction_fn,
        interval: interval
      }

      schedule_tick(interval)
      loop(state)
    end)
  end

  # Main loop

  defp loop(state) do
    receive do
      :tick ->
        if should_exit?() do
          exit_market(state)
        else
          state
          |> update_dwell_time()
          |> maybe_search()
          |> continue_loop()
        end
    end
  end

  defp continue_loop(state) do
    schedule_tick(state.interval)
    loop(state)
  end

  defp schedule_tick(interval) do
    Process.send_after(self(), :tick, interval)
  end

  # Exit behavior

  defp should_exit?, do: :rand.uniform() < @exit_probability

  defp exit_market(%{current_resource: nil}), do: :ok

  defp exit_market(%{current_resource: %{pid: pid}}) do
    send(pid, :vacate)
  end

  # Dwell time tracking

  defp update_dwell_time(%{current_resource: nil} = state), do: state

  defp update_dwell_time(%{current_resource: res} = state) do
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
    send(pid, {:occupy, self()})

    receive do
      {:ok, :acquired} -> acquire_success(pid, state)
      {:error, :already_occupied} -> state
    end
  end

  defp acquire_success(pid, state) do
    attrs = get_resource_attrs(pid)
    %{state | current_resource: %{pid: pid, ticks: 0, attrs: attrs}}
  end

  defp get_resource_attrs(pid) do
    send(pid, {:status, self()})

    receive do
      {:status_response, %{attributes: attrs}} -> attrs
    after
      1000 -> %{}
    end
  end
end
