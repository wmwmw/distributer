defmodule DistributerWeb.StripeWebhookControllerTest do
  # async: false — mutates the global :stripe application env.
  use DistributerWeb.ConnCase, async: false

  @secret "whsec_test_secret"

  setup do
    original = Application.get_env(:distributer, :stripe)

    Application.put_env(:distributer, :stripe,
      api_key: "sk_live_x",
      webhook_secret: @secret,
      platform_fee_percent: 3
    )

    on_exit(fn -> Application.put_env(:distributer, :stripe, original) end)
    :ok
  end

  defp sign(payload, timestamp) do
    sig =
      :crypto.mac(:hmac, :sha256, @secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{sig}"
  end

  defp post_webhook(conn, payload, signature) do
    conn
    |> put_req_header("content-type", "application/json")
    |> then(fn c -> if signature, do: put_req_header(c, "stripe-signature", signature), else: c end)
    |> post(~p"/webhooks/stripe", payload)
  end

  test "accepts a correctly signed benign event", %{conn: conn} do
    # A type we don't act on still verifies and returns 200.
    payload = ~s({"type":"charge.updated","data":{"object":{}}})
    conn = post_webhook(conn, payload, sign(payload, System.system_time(:second)))

    assert response(conn, 200) == "ok"
  end

  test "rejects an unsigned request", %{conn: conn} do
    conn = post_webhook(conn, ~s({"type":"charge.updated"}), nil)
    assert response(conn, 400)
  end

  test "rejects a tampered body", %{conn: conn} do
    header = sign(~s({"amount":100}), System.system_time(:second))
    conn = post_webhook(conn, ~s({"amount":999999}), header)
    assert response(conn, 400)
  end
end
