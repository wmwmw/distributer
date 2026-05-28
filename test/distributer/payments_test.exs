defmodule Distributer.PaymentsTest do
  # async: false — these tests mutate the global :stripe application env.
  use ExUnit.Case, async: false

  alias Distributer.Payments

  @secret "whsec_test_secret"

  defp with_stripe_config(opts) do
    original = Application.get_env(:distributer, :stripe)

    Application.put_env(
      :distributer,
      :stripe,
      Keyword.merge([platform_fee_percent: 3], opts)
    )

    on_exit(fn -> Application.put_env(:distributer, :stripe, original) end)
  end

  defp sign(payload, secret, timestamp) do
    sig =
      :crypto.mac(:hmac, :sha256, secret, "#{timestamp}.#{payload}")
      |> Base.encode16(case: :lower)

    "t=#{timestamp},v1=#{sig}"
  end

  describe "construct_event/2 with a real webhook secret" do
    setup do
      with_stripe_config(api_key: "sk_live_x", webhook_secret: @secret)
      :ok
    end

    test "accepts a correctly signed payload" do
      payload = ~s({"type":"payment_intent.succeeded"})
      header = sign(payload, @secret, System.system_time(:second))

      assert {:ok, %{"type" => "payment_intent.succeeded"}} =
               Payments.construct_event(payload, header)
    end

    test "rejects a tampered payload" do
      header = sign(~s({"amount":100}), @secret, System.system_time(:second))

      assert {:error, :signature_mismatch} =
               Payments.construct_event(~s({"amount":999999}), header)
    end

    test "rejects a signature made with the wrong secret" do
      payload = ~s({"type":"x"})
      header = sign(payload, "the_wrong_secret", System.system_time(:second))

      assert {:error, :signature_mismatch} = Payments.construct_event(payload, header)
    end

    test "rejects a stale timestamp (replay protection)" do
      payload = ~s({"type":"x"})
      stale = System.system_time(:second) - 10_000
      header = sign(payload, @secret, stale)

      assert {:error, :timestamp_out_of_tolerance} = Payments.construct_event(payload, header)
    end

    test "rejects a missing signature header" do
      assert {:error, :missing_signature} = Payments.construct_event(~s({}), nil)
    end

    test "rejects a malformed signature header" do
      assert {:error, :malformed_signature} =
               Payments.construct_event(~s({}), "not-a-valid-header")
    end
  end

  describe "stub mode (no real secret configured)" do
    setup do
      with_stripe_config(api_key: "sk_test_placeholder", webhook_secret: "whsec_placeholder")
      :ok
    end

    test "skips verification and parses the payload directly" do
      assert {:ok, %{"type" => "x"}} = Payments.construct_event(~s({"type":"x"}), nil)
    end

    test "reports stub mode" do
      assert Payments.stub_mode?()
      assert Payments.webhook_stub_mode?()
    end
  end
end
