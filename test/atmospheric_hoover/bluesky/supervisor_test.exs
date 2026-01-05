defmodule AtmosphericHoover.Bluesky.SupervisorTest do
  @moduledoc """
  Tests for the Bluesky Supervisor.
  """

  use ExUnit.Case, async: true

  alias AtmosphericHoover.Bluesky.Supervisor

  describe "enabled?/0" do
    test "returns true by default" do
      # Clear any config override
      original = Application.get_env(:atmospheric_hoover, Supervisor)
      Application.delete_env(:atmospheric_hoover, Supervisor)

      assert Supervisor.enabled?() == true

      # Restore
      if original, do: Application.put_env(:atmospheric_hoover, Supervisor, original)
    end

    test "returns false when disabled in config" do
      original = Application.get_env(:atmospheric_hoover, Supervisor)
      Application.put_env(:atmospheric_hoover, Supervisor, enabled: false)

      assert Supervisor.enabled?() == false

      # Restore
      if original do
        Application.put_env(:atmospheric_hoover, Supervisor, original)
      else
        Application.delete_env(:atmospheric_hoover, Supervisor)
      end
    end

    test "returns true when explicitly enabled" do
      original = Application.get_env(:atmospheric_hoover, Supervisor)
      Application.put_env(:atmospheric_hoover, Supervisor, enabled: true)

      assert Supervisor.enabled?() == true

      # Restore
      if original do
        Application.put_env(:atmospheric_hoover, Supervisor, original)
      else
        Application.delete_env(:atmospheric_hoover, Supervisor)
      end
    end
  end

  describe "child_spec/1" do
    test "returns a valid child spec" do
      spec = Supervisor.child_spec([])

      assert spec.id == Supervisor
      assert spec.start == {Supervisor, :start_link, [[]]}
      assert spec.type == :supervisor
    end

    test "allows custom options" do
      spec = Supervisor.child_spec(name: :custom_name)

      assert spec.start == {Supervisor, :start_link, [[name: :custom_name]]}
    end
  end

  describe "module info" do
    test "exports start_link/1" do
      exports = Supervisor.__info__(:functions)
      assert {:start_link, 1} in exports
    end

    test "exports enabled?/0" do
      exports = Supervisor.__info__(:functions)
      assert {:enabled?, 0} in exports
    end

    test "uses Supervisor behaviour" do
      # Check that init/1 callback is implemented
      exports = Supervisor.__info__(:functions)
      assert {:init, 1} in exports
    end
  end

  describe "documentation" do
    test "has module documentation" do
      {:docs_v1, _, _, _, module_doc, _, _} = Code.fetch_docs(Supervisor)
      assert module_doc != :hidden
      assert module_doc != :none
    end
  end
end
