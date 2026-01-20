defmodule Vacant.ResourceTest do
  use ExUnit.Case, async: false

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
    test "registers as vacant in ETS" do
      {:ok, pid} = Vacant.Resource.start_link(%{quality: 0.5})

      assert [{^pid, %{quality: 0.5}, :vacant}] = :ets.lookup(:listings, pid)
    end

    test "process stays alive" do
      {:ok, pid} = Vacant.Resource.start_link(%{quality: 0.5})

      assert Process.alive?(pid)
    end
  end

  describe "occupy" do
    test "succeeds when vacant" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      assert {:ok, :acquired} = Vacant.Resource.occupy(resource)
    end

    test "updates ETS to occupied" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      Vacant.Resource.occupy(resource)

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
    end

    test "fails when already occupied" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      Vacant.Resource.occupy(resource)

      assert {:error, :already_occupied} = Vacant.Resource.occupy(resource)
    end

    test "rejects second occupant" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      # First actor occupies
      Vacant.Resource.occupy(resource)

      # Simulate second actor trying to occupy
      other_actor =
        spawn(fn ->
          receive do
            {:try_occupy, res, reply_to} ->
              result = Vacant.Resource.occupy(res)
              send(reply_to, {:result, result})
          end
        end)

      send(other_actor, {:try_occupy, resource, self()})
      assert_receive {:result, {:error, :already_occupied}}
    end
  end

  describe "vacate" do
    test "makes resource vacant again" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      Vacant.Resource.occupy(resource)
      Vacant.Resource.vacate(resource)

      # Give it a moment to process (cast is async)
      :timer.sleep(10)

      assert [{^resource, _, :vacant}] = :ets.lookup(:listings, resource)
    end

    test "allows new occupant after vacate" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      Vacant.Resource.occupy(resource)
      Vacant.Resource.vacate(resource)
      :timer.sleep(10)

      assert {:ok, :acquired} = Vacant.Resource.occupy(resource)
    end
  end

  describe "status" do
    test "returns current state" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      status = Vacant.Resource.status(resource)

      assert %{attributes: %{quality: 0.5}, occupant: nil} = status
    end

    test "includes occupant when occupied" do
      {:ok, resource} = Vacant.Resource.start_link(%{quality: 0.5})

      Vacant.Resource.occupy(resource)

      status = Vacant.Resource.status(resource)

      assert %{attributes: %{quality: 0.5}, occupant: occupant} = status
      assert is_pid(occupant)
    end
  end
end
