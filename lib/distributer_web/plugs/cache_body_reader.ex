defmodule DistributerWeb.CacheBodyReader do
  @moduledoc """
  Custom body reader for `Plug.Parsers` that caches the raw, unparsed request
  body for webhook endpoints that need it for signature verification (Stripe
  signs the exact bytes of the payload).

  To keep memory bounded, the raw body is only retained for the paths in
  `@cached_paths`; every other request — including large multipart file
  uploads — is read and discarded as usual.
  """

  @cached_paths ["/webhooks/stripe"]

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)

    if conn.request_path in @cached_paths do
      conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
      {:ok, body, conn}
    else
      {:ok, body, conn}
    end
  end

  @doc "Returns the cached raw body for a request, or `nil` if none was cached."
  def raw_body(%Plug.Conn{assigns: %{raw_body: chunks}}) when is_list(chunks) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end

  def raw_body(_conn), do: nil
end
