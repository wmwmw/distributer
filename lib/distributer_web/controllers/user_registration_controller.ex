defmodule DistributerWeb.UserRegistrationController do
  use DistributerWeb, :controller

  alias Distributer.Accounts
  alias DistributerWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%Accounts.User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Welcome to Distributer!")
        |> UserAuth.log_in_user(user)

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end
end
