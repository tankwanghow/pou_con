defmodule PouCon.AuthTest do
  # Remove async: false
  use PouCon.DataCase

  alias PouCon.Auth
  alias PouCon.Auth.AppConfig
  alias PouCon.Repo

  describe "verify_password/2" do
    setup do
      # Clean up any existing configs
      Repo.delete_all(AppConfig)

      # Set up admin password
      %AppConfig{}
      |> AppConfig.changeset(%{key: "admin_password", password: "admin123"})
      |> Repo.insert!()

      # Set up user password
      %AppConfig{}
      |> AppConfig.changeset(%{key: "user_password", password: "user123"})
      |> Repo.insert!()

      :ok
    end

    test "verifies correct admin password" do
      assert {:ok, :admin} = Auth.verify_password("admin123", :admin)
    end

    test "verifies correct user password" do
      assert {:ok, :user} = Auth.verify_password("user123", :user)
    end

    test "rejects incorrect admin password" do
      assert {:error, :invalid_password} = Auth.verify_password("wrong", :admin)
    end

    test "rejects incorrect user password" do
      assert {:error, :invalid_password} = Auth.verify_password("wrong", :user)
    end

    test "defaults to admin role when not specified" do
      assert {:ok, :admin} = Auth.verify_password("admin123")
    end

    test "returns error when config not set" do
      # Clear the database
      Repo.delete_all(AppConfig)
      assert {:error, :no_config_set} = Auth.verify_password("anything", :admin)
    end
  end

  describe "password_exists?/1" do
    setup do
      Repo.delete_all(AppConfig)
      :ok
    end

    test "returns true when admin password exists" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "admin_password", password: "admin123"})
      |> Repo.insert!()

      assert Auth.password_exists?(:admin) == true
    end

    test "returns true when user password exists" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "user_password", password: "user123"})
      |> Repo.insert!()

      assert Auth.password_exists?(:user) == true
    end

    test "returns false when password not set" do
      assert Auth.password_exists?(:admin) == false
    end

    test "defaults to admin role when not specified" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "admin_password", password: "admin123"})
      |> Repo.insert!()

      assert Auth.password_exists?() == true
    end
  end

  describe "update_password/2" do
    setup do
      Repo.delete_all(AppConfig)

      %AppConfig{}
      |> AppConfig.changeset(%{key: "admin_password", password: "oldpass"})
      |> Repo.insert!()

      :ok
    end

    test "updates admin password successfully" do
      assert {:ok, _config} = Auth.update_password("newpass123", :admin)
      assert {:ok, :admin} = Auth.verify_password("newpass123", :admin)
      assert {:error, :invalid_password} = Auth.verify_password("oldpass", :admin)
    end

    test "returns error when config not set" do
      Repo.delete_all(AppConfig)
      assert {:error, :no_config_set} = Auth.update_password("newpass", :admin)
    end

    test "defaults to admin role when not specified" do
      assert {:ok, _config} = Auth.update_password("newpass456")
      assert {:ok, :admin} = Auth.verify_password("newpass456")
    end
  end

  describe "get_house_id/0" do
    setup do
      Repo.delete_all(AppConfig)
      :ok
    end

    test "returns house ID when set" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "house_id", value: "HOUSE-123"})
      |> Repo.insert!()

      assert Auth.get_house_id() == "HOUSE-123"
    end

    test "returns default message when not set" do
      assert Auth.get_house_id() == "House ID Not Set"
    end

    test "returns default message when value is nil" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "house_id"})
      |> Repo.insert!()

      assert Auth.get_house_id() == "House ID Not Set"
    end
  end

  describe "set_house_id/1" do
    setup do
      Repo.delete_all(AppConfig)
      :ok
    end

    test "creates new house ID when not exists" do
      assert {:ok, config} = Auth.set_house_id("HOUSE-456")
      assert config.key == "house_id"
      assert config.value == "HOUSE-456"
      assert Auth.get_house_id() == "HOUSE-456"
    end

    test "updates existing house ID" do
      %AppConfig{}
      |> AppConfig.changeset(%{key: "house_id", value: "OLD-ID"})
      |> Repo.insert!()

      assert {:ok, config} = Auth.set_house_id("NEW-ID")
      assert config.value == "NEW-ID"
      assert Auth.get_house_id() == "NEW-ID"
    end
  end
end
