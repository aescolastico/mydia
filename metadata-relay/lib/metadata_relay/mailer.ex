defmodule MetadataRelay.Mailer do
  @moduledoc """
  Delivers operational email for the metadata relay service.
  """

  use Swoosh.Mailer, otp_app: :metadata_relay
end
