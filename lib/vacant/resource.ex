defmodule Vacant.Resource do
  def start(attributes) do
    spawn(fn ->
      pid = self()
      :ets.insert(:listings, {pid, attributes, :vacant})
      loop(%{attributes: attributes, occupant: nil})
    end)
  end

  def loop(%{attributes: attributes, occupant: occupant} = state) do
    receive do
      :vacate ->
        :ets.insert(:listings, {self(), attributes, :vacant})
        loop(%{state | occupant: nil})

      {:occupy, from} when occupant == nil ->
        :ets.insert(:listings, {self(), attributes, :occupied})
        send(from, {:ok, :acquired})
        loop(%{state | occupant: from})

      {:occupy, from} ->
        send(from, {:error, :already_occupied})
        loop(state)

      {:status, from} ->
        send(from, {:status_response, state})
        loop(state)
    end
  end
end
