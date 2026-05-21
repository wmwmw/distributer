defmodule Distributer.Storage do
  @moduledoc """
  Pluggable storage. Local filesystem in dev, S3-compatible in prod.
  Returns opaque storage keys that the adapter can resolve back to bytes.
  """

  @callback put(binary(), iodata()) :: {:ok, String.t()} | {:error, term()}
  @callback get(String.t()) :: {:ok, binary()} | {:error, term()}
  @callback url(String.t()) :: String.t()
  @callback delete(String.t()) :: :ok | {:error, term()}

  def put(key, contents), do: adapter().put(key, contents)
  def get(key), do: adapter().get(key)
  def url(key), do: adapter().url(key)
  def delete(key), do: adapter().delete(key)

  @doc """
  Generate a unique storage key with the given prefix and file extension.
  """
  def new_key(prefix, ext) do
    rand = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    "#{prefix}/#{rand}.#{ext}"
  end

  defp adapter do
    Application.get_env(:distributer, :storage)[:adapter] || Distributer.Storage.Local
  end
end
