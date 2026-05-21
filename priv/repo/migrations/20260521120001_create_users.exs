defmodule Distributer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :citext, null: false
      add :hashed_password, :string, null: false
      add :confirmed_at, :utc_datetime
      add :role, :string, null: false, default: "user"
      add :display_name, :string
      # Stripe Connect account id (for sellers)
      add :stripe_account_id, :string
      add :stripe_kyc_status, :string, default: "none"
      # Czech tax info (sellers only)
      add :vat_id, :string
      add :is_vat_payer, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    execute "CREATE EXTENSION IF NOT EXISTS citext", ""
    create unique_index(:users, [:email])
    create index(:users, [:role])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
