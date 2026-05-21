defmodule Distributer.Accounts do
  @moduledoc """
  Users, authentication, sessions.
  Sellers and buyers are both `users` — the `role` field plus the existence of an
  associated `Shop` determine seller capabilities. There is no separate seller table.
  """

  import Ecto.Query, warn: false
  alias Distributer.Repo
  alias Distributer.Accounts.{User, UserToken}

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  def promote_to_seller(%User{} = user) do
    user
    |> User.role_changeset(%{role: "seller"})
    |> Repo.update()
  end

  def update_seller_profile(%User{} = user, attrs) do
    user
    |> User.seller_profile_changeset(attrs)
    |> Repo.update()
  end

  # Session tokens

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end
end
