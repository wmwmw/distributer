defmodule DistributerWeb.UserRegistrationHTML do
  use DistributerWeb, :html

  def new(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Register for an account
        <:subtitle>
          Already registered?
          <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
            Log in
          </.link>
          here.
        </:subtitle>
      </.header>

      <.simple_form :let={f} for={@changeset} as={:user} action={~p"/users/register"}>
        <.error :if={@changeset.action == :insert}>
          Oops, something went wrong! Please check the errors below.
        </.error>

        <.input field={f[:email]} type="email" label="Email" required />
        <.input field={f[:display_name]} type="text" label="Display name" />
        <.input field={f[:password]} type="password" label="Password (min 12 chars)" required />

        <:actions>
          <.button phx-disable-with="Creating account..." class="w-full">
            Create account
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end
end
