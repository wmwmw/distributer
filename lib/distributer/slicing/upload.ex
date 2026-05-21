defmodule Distributer.Slicing.Upload do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @timestamps_opts [type: :utc_datetime]

  schema "uploads" do
    field :original_filename, :string
    field :format, :string
    field :storage_key, :string
    field :size_bytes, :integer
    field :sha256, :string
    field :bbox_x_mm, :decimal
    field :bbox_y_mm, :decimal
    field :bbox_z_mm, :decimal
    field :volume_mm3, :decimal
    field :analysis_status, :string, default: "pending"
    field :analysis_error, :string
    field :intent_text, :string

    belongs_to :user, Distributer.Accounts.User

    timestamps()
  end

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, [
      :user_id, :original_filename, :format, :storage_key, :size_bytes,
      :sha256, :bbox_x_mm, :bbox_y_mm, :bbox_z_mm, :volume_mm3,
      :analysis_status, :analysis_error, :intent_text
    ])
    |> validate_required([:original_filename, :format, :storage_key, :size_bytes, :sha256])
    |> validate_inclusion(:format, ~w(stl 3mf))
    |> validate_inclusion(:analysis_status, ~w(pending analyzed failed))
    |> unique_constraint(:sha256)
  end
end
