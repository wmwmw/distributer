defmodule Distributer.Storage.S3 do
  @moduledoc """
  S3-compatible storage adapter. Configure via:

      config :distributer, :storage,
        adapter: Distributer.Storage.S3,
        bucket: "distributer-prod",
        region: "eu-central-1"

  Used in prod with Backblaze B2 or Hetzner Object Storage.
  """
  @behaviour Distributer.Storage

  @impl true
  def put(key, contents) do
    case ExAws.S3.put_object(bucket(), key, contents) |> ExAws.request() do
      {:ok, _} -> {:ok, key}
      err -> err
    end
  end

  @impl true
  def get(key) do
    case ExAws.S3.get_object(bucket(), key) |> ExAws.request() do
      {:ok, %{body: body}} -> {:ok, body}
      err -> err
    end
  end

  @impl true
  def url(key) do
    {:ok, url} =
      :s3
      |> ExAws.Config.new()
      |> ExAws.S3.presigned_url(:get, bucket(), key, expires_in: 3600)

    url
  end

  @impl true
  def delete(key) do
    case ExAws.S3.delete_object(bucket(), key) |> ExAws.request() do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp bucket, do: Application.fetch_env!(:distributer, :storage)[:bucket]
end
