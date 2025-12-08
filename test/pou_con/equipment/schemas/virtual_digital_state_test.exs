defmodule PouCon.Equipment.Schemas.VirtualDigitalStateTest do
  # Remove async: false to avoid SQLite database busy errors
  use PouCon.DataCase

  alias PouCon.Equipment.Schemas.VirtualDigitalState

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{
          slave_id: 1,
          channel: 5,
          state: 1
        })

      assert changeset.valid?
    end

    test "requires slave_id field" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{channel: 1, state: 0})

      refute changeset.valid?
      assert %{slave_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "requires channel field" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, state: 0})

      refute changeset.valid?
      assert %{channel: ["can't be blank"]} = errors_on(changeset)
    end

    test "uses default state value when state not provided" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1})

      assert changeset.valid?
      # State has default value of 0, so it won't fail validation
      # Not changed, using default
      assert get_change(changeset, :state) == nil
    end

    test "validates state is 0 or 1" do
      # Invalid state value
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1, state: 2})

      refute changeset.valid?
      assert %{state: ["is invalid"]} = errors_on(changeset)
    end

    test "accepts state value 0" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1, state: 0})

      assert changeset.valid?
    end

    test "accepts state value 1" do
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1, state: 1})

      assert changeset.valid?
    end

    test "validates unique constraint on slave_id and channel" do
      # Insert first virtual state
      %VirtualDigitalState{}
      |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 5, state: 0})
      |> Repo.insert!()

      # Try to insert duplicate slave_id + channel
      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 5, state: 1})

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{slave_id: ["has already been taken"]} = errors_on(changeset)
    end

    test "allows same slave_id with different channel" do
      %VirtualDigitalState{}
      |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1, state: 0})
      |> Repo.insert!()

      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 2, state: 1})

      assert {:ok, _} = Repo.insert(changeset)
    end

    test "allows same channel with different slave_id" do
      %VirtualDigitalState{}
      |> VirtualDigitalState.changeset(%{slave_id: 1, channel: 1, state: 0})
      |> Repo.insert!()

      changeset =
        %VirtualDigitalState{}
        |> VirtualDigitalState.changeset(%{slave_id: 2, channel: 1, state: 1})

      assert {:ok, _} = Repo.insert(changeset)
    end

    test "default state value is 0" do
      virtual_state = %VirtualDigitalState{}
      assert virtual_state.state == 0
    end
  end
end
