defmodule PouCon.Auth.Auth.AppConfigTest do
  use PouCon.DataCase, async: true

  alias PouCon.Auth.Auth.Auth.AppConfig

  describe "changeset/2" do
    test "valid changeset with password" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test_key", password: "password123"})

      assert changeset.valid?
      assert get_change(changeset, :password_hash) != nil
      assert get_change(changeset, :password_hash) != "password123"
    end

    test "valid changeset with key and value" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "house_id", value: "HOUSE-123"})

      assert changeset.valid?
      assert get_change(changeset, :key) == "house_id"
      assert get_change(changeset, :value) == "HOUSE-123"
    end

    test "hashes password when provided" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", password: "mypassword"})

      password_hash = get_change(changeset, :password_hash)
      assert password_hash != nil
      assert String.starts_with?(password_hash, "$2b$")
      assert Bcrypt.verify_pass("mypassword", password_hash)
    end

    test "does not hash when password not provided" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", value: "some_value"})

      assert get_change(changeset, :password_hash) == nil
    end

    test "requires key field" do
      changeset = AppConfig.changeset(%AppConfig{}, %{})
      refute changeset.valid?
      assert %{key: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates password minimum length" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", password: "short"})

      refute changeset.valid?
      assert %{password: ["must be at least 6 characters long"]} = errors_on(changeset)
    end

    test "accepts password with exactly 6 characters" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", password: "123456"})

      assert changeset.valid?
    end

    test "accepts password longer than 6 characters" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", password: "longpassword123"})

      assert changeset.valid?
    end

    test "does not validate password length when password not provided" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test"})

      assert changeset.valid?
    end

    test "does not validate password length when password is nil" do
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "test", password: nil})

      assert changeset.valid?
    end

    test "validates unique key constraint" do
      # Insert first config
      %AppConfig{}
      |> AppConfig.changeset(%{key: "unique_key", value: "value1"})
      |> Repo.insert!()

      # Try to insert duplicate key
      changeset =
        %AppConfig{}
        |> AppConfig.changeset(%{key: "unique_key", value: "value2"})

      assert {:error, changeset} = Repo.insert(changeset)
      assert %{key: ["has already been taken"]} = errors_on(changeset)
    end
  end
end
