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
      # Create a temporary file for testing
      test_file = Path.join(System.tmp_dir!(), "test_house_id_#{:rand.uniform(100_000)}")
      Application.put_env(:pou_con, :house_id_file, test_file)

      on_exit(fn ->
        File.rm(test_file)
        Application.delete_env(:pou_con, :house_id_file)
      end)

      {:ok, test_file: test_file}
    end

    test "returns house ID when file exists", %{test_file: test_file} do
      File.write!(test_file, "house-123\n")
      assert Auth.get_house_id() == "HOUSE-123"
    end

    test "returns uppercase house ID", %{test_file: test_file} do
      File.write!(test_file, "h1")
      assert Auth.get_house_id() == "H1"
    end

    test "trims whitespace from house ID", %{test_file: test_file} do
      File.write!(test_file, "  farm_a  \n")
      assert Auth.get_house_id() == "FARM_A"
    end

    test "returns NOT SET when file does not exist" do
      assert Auth.get_house_id() == "NOT SET"
    end

    test "returns NOT SET when file is empty", %{test_file: test_file} do
      File.write!(test_file, "")
      assert Auth.get_house_id() == "NOT SET"
    end

    test "returns NOT SET when file contains only whitespace", %{test_file: test_file} do
      File.write!(test_file, "   \n  ")
      assert Auth.get_house_id() == "NOT SET"
    end
  end
end
