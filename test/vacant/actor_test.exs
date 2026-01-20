defmodule Vacant.ActorTest do
  use ExUnit.Case, async: false

  # Simple utility: always returns quality
  defp simple_utility(attrs), do: Map.get(attrs, :quality, 0)

  # Always satisfied (never searches if has resource)
  defp always_satisfied(_attrs, _ticks), do: 1.0

  # Never satisfied (always searches)
  defp never_satisfied(_attrs, _ticks), do: -1.0

  # Satisfied for N ticks, then dissatisfied
  defp satisfied_for(n) do
    fn _attrs, ticks ->
      if ticks < n, do: 1.0, else: -1.0
    end
  end

  setup do
    # Delete if exists from previous test
    try do
      :ets.delete(:listings)
    catch
      :error, :badarg -> :ok
    end

    # Create fresh ETS table for each test
    :ets.new(:listings, [:set, :public, :named_table])
    :ok
  end

  describe "start/3" do
    test "creates a living process" do
      pid = Vacant.Actor.start(&simple_utility/1, &always_satisfied/2, 1000, exit_probability: 0, link: true)

      assert Process.alive?(pid)
    end
  end

  describe "resource acquisition" do
    test "acquires vacant resource when resourceless" do
      resource = Vacant.Resource.start(%{quality: 0.8})
      :timer.sleep(10)  # Wait for resource to register

      _actor = Vacant.Actor.start(&simple_utility/1, &always_satisfied/2, 50, exit_probability: 0, link: true)

      # Wait for actor to tick and acquire
      :timer.sleep(150)

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
    end

    test "acquires best resource by utility" do
      low = Vacant.Resource.start(%{quality: 0.2})
      high = Vacant.Resource.start(%{quality: 0.9})
      :timer.sleep(10)  # Wait for resources to register

      _actor = Vacant.Actor.start(&simple_utility/1, &always_satisfied/2, 50, exit_probability: 0, link: true)

      :timer.sleep(150)

      # High quality should be occupied, low should be vacant
      assert [{^high, _, :occupied}] = :ets.lookup(:listings, high)
      assert [{^low, _, :vacant}] = :ets.lookup(:listings, low)
    end

    test "does nothing when no vacant resources" do
      resource = Vacant.Resource.start(%{quality: 0.5})
      :timer.sleep(10)

      # Occupy the only resource
      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      # Actor starts but finds nothing
      actor = Vacant.Actor.start(&simple_utility/1, &always_satisfied/2, 50, exit_probability: 0, link: true)

      :timer.sleep(150)

      # Actor should still be alive, waiting
      assert Process.alive?(actor)
    end
  end

  describe "chain propagation" do
    test "releases old resource when acquiring new one" do
      # Actor will acquire first, then when dissatisfied, acquire second
      first = Vacant.Resource.start(%{quality: 0.3})
      :timer.sleep(20)  # Wait for resource to register

      # Start actor - dissatisfied after 1 tick (so it switches on tick 2)
      _actor = Vacant.Actor.start(&simple_utility/1, satisfied_for(1), 50, exit_probability: 0, link: true)

      # Wait for initial acquisition
      :timer.sleep(100)
      assert [{^first, _, :occupied}] = :ets.lookup(:listings, first)

      # Add better resource
      second = Vacant.Resource.start(%{quality: 0.9})
      :timer.sleep(20)  # Wait for resource to register

      # Wait for actor to become dissatisfied and switch (multiple ticks)
      :timer.sleep(500)

      # First should be vacant (released), second should be occupied
      assert [{^first, _, :vacant}] = :ets.lookup(:listings, first)
      assert [{^second, _, :occupied}] = :ets.lookup(:listings, second)
    end
  end

  describe "satisfaction function" do
    test "does not search when satisfied" do
      resource = Vacant.Resource.start(%{quality: 0.5})
      :timer.sleep(10)  # Wait for resource to register

      _actor = Vacant.Actor.start(&simple_utility/1, &always_satisfied/2, 50, exit_probability: 0, link: true)

      :timer.sleep(150)
      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)

      # Add another resource
      second = Vacant.Resource.start(%{quality: 0.9})
      :timer.sleep(10)

      # Wait - actor should NOT switch because always satisfied
      :timer.sleep(200)

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
      assert [{^second, _, :vacant}] = :ets.lookup(:listings, second)
    end

    test "searches when dissatisfied" do
      first = Vacant.Resource.start(%{quality: 0.3})
      :timer.sleep(10)

      # Never satisfied - will always look for better
      _actor = Vacant.Actor.start(&simple_utility/1, &never_satisfied/2, 50, exit_probability: 0, link: true)

      :timer.sleep(150)
      assert [{^first, _, :occupied}] = :ets.lookup(:listings, first)

      # Add better resource
      second = Vacant.Resource.start(%{quality: 0.9})
      :timer.sleep(10)

      :timer.sleep(200)

      # Should have switched to better resource
      assert [{^first, _, :vacant}] = :ets.lookup(:listings, first)
      assert [{^second, _, :occupied}] = :ets.lookup(:listings, second)
    end
  end
end
