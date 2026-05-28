defmodule Distributer.Storage.Local do
  @moduledoc "Filesystem-backed storage. Used in dev/test."
  @behaviour Distributer.Storage

  @impl true
  def put(key, contents) do
    path = full_path(key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
    {:ok, key}
  end

  @impl true
  def get(key) do
    case File.read(full_path(key)) do
      {:ok, data} -> {:ok, data}
      err -> err
    end
  end

  @impl true
  def url(key), do: "/uploads/#{key}"

  @impl true
  def delete(key) do
    case File.rm(full_path(key)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      err -> err
    end
  end

  def full_path(key) do
    base = Application.get_env(:distributer, :storage)[:upload_dir] || "priv/uploads"
    Path.join(base, safe_key(key))
  end

  # Reject absolute paths and any `..` traversal so a crafted key can never
  # escape the upload directory.
  defp safe_key(key) when is_binary(key) do
    if Path.type(key) != :relative or ".." in Path.split(key) do
      raise ArgumentError, "unsafe storage key: #{inspect(key)}"
    end

    key
  end
end
