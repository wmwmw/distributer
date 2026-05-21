defmodule DistributerWeb.Router do
  use DistributerWeb, :router

  import DistributerWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {DistributerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # -------------------- Public routes --------------------
  scope "/", DistributerWeb do
    pipe_through :browser

    live_session :public,
      on_mount: [{DistributerWeb.UserAuth, :mount_current_user}] do
      live "/", HomeLive
      live "/upload", UploadLive
      live "/shops/:slug", ShopShowLive
    end
  end

  # -------------------- Auth routes (guest-only) --------------------
  scope "/", DistributerWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/users/register", UserRegistrationController, :new
    post "/users/register", UserRegistrationController, :create
    get "/users/log_in", UserSessionController, :new
    post "/users/log_in", UserSessionController, :create
  end

  # -------------------- Authenticated routes --------------------
  scope "/", DistributerWeb do
    pipe_through [:browser, :require_authenticated_user]

    delete "/users/log_out", UserSessionController, :delete

    live_session :authenticated,
      on_mount: [{DistributerWeb.UserAuth, :ensure_authenticated}] do
      live "/orders/new", OrderNewLive
      live "/orders/:id", OrderShowLive
      live "/sellers/onboarding", SellerOnboardingLive
    end

    live_session :seller,
      on_mount: [{DistributerWeb.UserAuth, :ensure_seller}] do
      live "/sellers", SellerDashboardLive
      live "/sellers/printers/new", SellerPrinterNewLive
      live "/sellers/spools/new", SellerSpoolNewLive
    end
  end

  # -------------------- Webhooks (API) --------------------
  scope "/webhooks", DistributerWeb do
    pipe_through :api

    post "/stripe", StripeWebhookController, :create
  end

  # -------------------- Dev routes --------------------
  if Application.compile_env(:distributer, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: DistributerWeb.Telemetry
    end
  end
end
