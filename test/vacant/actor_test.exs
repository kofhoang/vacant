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

  describe "start_link/1" do
    test "creates a living process" do
      {:ok, pid} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &always_satisfied/2,
        interval: 1000,
        exit_probability: 0
      })

      assert Process.alive?(pid)
    end
  end

  describe "resource acquisition" do
    test "acquires vacant resource when resourceless" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.8})
      :timer.sleep(10)  # Wait for resource to register

      {:ok, _actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &always_satisfied/2,
        interval: 50,
        exit_probability: 0
      })

      # Wait for actor to tick and acquire
      :timer.sleep(150)

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
    end

    test "acquires best resource by utility" do
      {:ok, low} = Vacant.Resource.start_link(%{quality: 0.2})
      {:ok, high} = Vacant.Resource.start_link(%{quality: 0.9})
      :timer.sleep(10)  # Wait for resources to register

      {:ok, _actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &always_satisfied/2,
        interval: 50,
        exit_probability: 0
      })

      :timer.sleep(150)

      # High quality should be occupied, low should be vacant
      assert [{^high, _, :occupied}] = :ets.lookup(:listings, high)
      assert [{^low, _, :vacant}] = :ets.lookup(:listings, low)
    end

    test "does nothing when no vacant resources" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})
      :timer.sleep(10)

      # Occupy the only resource
      Vacant.Resource.occupy(resource)

      # Actor starts but finds nothing
      {:ok, actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &always_satisfied/2,
        interval: 50,
        exit_probability: 0
      })

      :timer.sleep(150)

      # Actor should still be alive, waiting
      assert Process.alive?(actor)
    end
  end

  describe "chain propagation" do
    test "releases old resource when acquiring new one" do
      # Actor will acquire first, then when dissatisfied, acquire second
      {:ok, first} = Vacant.Resource.start_link(%{quality: 0.3})
      :timer.sleep(20)  # Wait for resource to register

      # Start actor - dissatisfied after 1 tick (so it switches on tick 2)
      {:ok, _actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: satisfied_for(1),
        interval: 50,
        exit_probability: 0
      })

      # Wait for initial acquisition
      :timer.sleep(100)
      assert [{^first, _, :occupied}] = :ets.lookup(:listings, first)

      # Add better resource
      {:ok, second} = Vacant.Resource.start_link(%{quality: 0.9})
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
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})
      :timer.sleep(10)  # Wait for resource to register

      {:ok, _actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &always_satisfied/2,
        interval: 50,
        exit_probability: 0
      })

      :timer.sleep(150)
      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)

      # Add another resource
      {:ok, second} = Vacant.Resource.start_link(%{quality: 0.9})
      :timer.sleep(10)

      # Wait - actor should NOT switch because always satisfied
      :timer.sleep(200)

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
      assert [{^second, _, :vacant}] = :ets.lookup(:listings, second)
    end

    test "searches when dissatisfied" do
      {:ok, first} = Vacant.Resource.start_link(%{quality: 0.3})
      :timer.sleep(10)

      # Never satisfied - will always look for better
      {:ok, _actor} = Vacant.Actor.start_link(%{
        utility_fn: &simple_utility/1,
        satisfaction_fn: &never_satisfied/2,
        interval: 50,
        exit_probability: 0
      })

      :timer.sleep(150)
      assert [{^first, _, :occupied}] = :ets.lookup(:listings, first)

      # Add better resource
      {:ok, second} = Vacant.Resource.start_link(%{quality: 0.9})
      :timer.sleep(10)

      :timer.sleep(200)

      # Should have switched to better resource
      assert [{^first, _, :vacant}] = :ets.lookup(:listings, first)
      assert [{^second, _, :occupied}] = :ets.lookup(:listings, second)
    end
  end
end
