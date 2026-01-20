defmodule Vacant.Resource do
  use GenServer

  def occupy(pid), do: GenServer.call(pid, :occupy)
  def vacate(pid), do: GenServer.cast(pid, :vacate)
  def status(pid), do: GenServer.call(pid, :get_status)

  def start_link(default) do
    GenServer.start_link(__MODULE__, default)
  end

  def init(attrs) do
    :ets.insert(:listings, {self(), attrs, :vacant})
    {:ok, %{attributes: attrs, occupant: nil}}
  end

  def handle_call(:occupy, {caller_pid, _ref}, %{occupant: nil} = state) do
    :ets.insert(:listings, {self(), state.attributes, :occupied})
    {:reply, {:ok, :acquired}, %{state | occupant: caller_pid}}
  end

  def handle_call(:occupy, _from, state) do
    {:reply, {:error, :already_occupied}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(:vacate, state) do
    :ets.insert(:listings, {self(), state.attributes, :vacant})
    {:noreply, %{state | occupant: nil}}
  end
end
