defmodule DistributerWeb.UserSessionHTML do
  use DistributerWeb, :html

  def new(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in to your account
        <:subtitle>
          Don't have an account?
          <.link navigate={~p"/users/register"} class="font-semibold text-brand hover:underline">
            Sign up
          </.link>
          for one.
        </:subtitle>
      </.header>

      <.simple_form :let={f} for={%{}} as={:user} action={~p"/users/log_in"}>
        <.input field={f[:email]} type="email" label="Email" required />
        <.input field={f[:password]} type="password" label="Password" required />
        <.input field={f[:remember_me]} type="checkbox" label="Keep me logged in" />
        <:actions>
          <.button phx-disable-with="Logging in..." class="w-full">
            Log in <span aria-hidden="true">→</span>
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
