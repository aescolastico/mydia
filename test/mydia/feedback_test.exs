defmodule Mydia.FeedbackTest do
  use Mydia.DataCase

  alias Mydia.Feedback
  alias Mydia.Settings

  test "enabled?/0 defaults on when no setting exists" do
    assert Feedback.enabled?()
  end

  test "enabled?/0 reads a false database setting" do
    assert {:ok, _setting} =
             Settings.create_config_setting(%{
               key: "feedback.enabled",
               value: "false",
               category: :feedback
             })

    refute Feedback.enabled?()
  end

  test "feedback category can be persisted" do
    assert {:ok, setting} =
             Settings.create_config_setting(%{
               key: "feedback.enabled",
               value: "false",
               category: :feedback
             })

    assert setting.category == :feedback
  end
end
