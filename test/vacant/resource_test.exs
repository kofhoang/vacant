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

  describe "start/1" do
    test "registers as vacant in ETS" do
      pid = Vacant.Resource.start(%{quality: 0.5})

      # Give spawned process time to execute
      :timer.sleep(10)

      assert [{^pid, %{quality: 0.5}, :vacant}] = :ets.lookup(:listings, pid)
    end

    test "process stays alive" do
      pid = Vacant.Resource.start(%{quality: 0.5})

      assert Process.alive?(pid)
    end
  end

  describe "occupy" do
    test "succeeds when vacant" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})

      assert_receive {:ok, :acquired}
    end

    test "updates ETS to occupied" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      assert [{^resource, _, :occupied}] = :ets.lookup(:listings, resource)
    end

    test "fails when already occupied" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      send(resource, {:occupy, self()})
      assert_receive {:error, :already_occupied}
    end

    test "rejects second occupant" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      # First actor occupies
      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      # Simulate second actor trying to occupy
      other_actor = spawn(fn ->
        receive do
          {:try_occupy, resource, reply_to} ->
            send(resource, {:occupy, self()})
            receive do
              response -> send(reply_to, {:result, response})
            end
        end
      end)

      send(other_actor, {:try_occupy, resource, self()})
      assert_receive {:result, {:error, :already_occupied}}
    end
  end

  describe "vacate" do
    test "makes resource vacant again" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      send(resource, :vacate)

      # Give it a moment to process
      :timer.sleep(10)

      assert [{^resource, _, :vacant}] = :ets.lookup(:listings, resource)
    end

    test "allows new occupant after vacate" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      send(resource, :vacate)
      :timer.sleep(10)

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}
    end
  end

  describe "status" do
    test "returns current state" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:status, self()})

      assert_receive {:status_response, %{attributes: %{quality: 0.5}, occupant: nil}}
    end

    test "includes occupant when occupied" do
      resource = Vacant.Resource.start(%{quality: 0.5})

      send(resource, {:occupy, self()})
      assert_receive {:ok, :acquired}

      send(resource, {:status, self()})

      assert_receive {:status_response, %{attributes: %{quality: 0.5}, occupant: occupant}}
      assert occupant == self()
    end
  end
end
