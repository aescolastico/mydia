defmodule Mydia.Accounts.UpdateUserRoleTest do
  use Mydia.DataCase, async: true

  alias Mydia.Accounts
  alias Mydia.Accounts.User

  describe "update_user_role/2" do
    test "updates the role of an OIDC user that has a nil username" do
      # OIDC users are created without a username, which the full
      # changeset/2 requires. update_user_role/2 must not trip on that.
      {:ok, oidc_user} =
        %User{}
        |> User.oidc_changeset(%{
          oidc_sub: "oidc-sub-role",
          oidc_issuer: "google",
          email: "oidc_role@example.com",
          display_name: "OIDC User",
          role: "user"
        })
        |> Repo.insert()

      assert is_nil(oidc_user.username)

      assert {:ok, updated} = Accounts.update_user_role(oidc_user, %{role: "admin"})
      assert updated.role == "admin"
      assert updated.id == oidc_user.id
    end

    test "updates the role of a local user" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "localuser",
          email: "local@example.com",
          password: "password123",
          role: "user"
        })

      assert {:ok, updated} = Accounts.update_user_role(user, %{role: "readonly"})
      assert updated.role == "readonly"
    end

    test "rejects an invalid role" do
      {:ok, user} =
        Accounts.create_user(%{
          username: "localuser2",
          email: "local2@example.com",
          password: "password123",
          role: "user"
        })

      assert {:error, changeset} = Accounts.update_user_role(user, %{role: "superuser"})
      assert %{role: ["is invalid"]} = errors_on(changeset)
    end
  end
end
