defmodule MetadataRelay.FeedbackIngestTest do
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias MetadataRelay.Feedback
  alias MetadataRelay.Feedback.Submission
  alias MetadataRelay.Repo
  alias MetadataRelay.Router

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Repo.delete_all(Submission)

    case GenServer.whereis(MetadataRelay.RateLimiter) do
      nil -> start_supervised!(MetadataRelay.RateLimiter)
      _pid -> :ok
    end

    :ets.delete_all_objects(:rate_limiter)

    :ok
  end

  describe "POST /feedback" do
    test "stores valid feedback" do
      conn =
        post_feedback(%{
          "type" => "bug",
          "message" => "Playback froze",
          "contact" => "user@example.com",
          "instance_id" => "instance-1",
          "mydia_version" => "1.2.3"
        })

      assert conn.status == 201
      assert %{"status" => "created", "id" => id} = Jason.decode!(conn.resp_body)

      submission = Feedback.get_submission!(id)
      assert submission.type == "bug"
      assert submission.message == "Playback froze"
      assert submission.contact == "user@example.com"
      assert submission.instance_id == "instance-1"
      assert submission.mydia_version == "1.2.3"
      assert submission.source_ip == "127.0.0.1"

      assert_email_sent(
        to: "maintainer@example.com",
        from: "metadata-relay@example.com",
        subject: "[Mydia feedback] bug: Playback froze"
      )
    end

    test "includes submission details in the notification email" do
      conn =
        post_feedback(%{
          "type" => "idea",
          "message" => "Add watch party mode",
          "contact" => "user@example.com",
          "instance_id" => "instance-1",
          "mydia_version" => "1.2.3"
        })

      assert conn.status == 201

      assert_email_sent(fn email ->
        assert email.text_body =~ "Type: idea"
        assert email.text_body =~ "Contact: user@example.com"
        assert email.text_body =~ "Instance: instance-1"
        assert email.text_body =~ "Mydia version: 1.2.3"
        assert email.text_body =~ "Message:\nAdd watch party mode"
        assert email.text_body =~ "Dashboard: https://relay.example.com/feedback#feedback-"
      end)
    end

    test "returns 400 when type is missing" do
      conn = post_feedback(%{"message" => "Playback froze"})

      assert conn.status == 400
      assert %{"error" => "Validation failed", "errors" => errors} = Jason.decode!(conn.resp_body)
      assert "Missing required field: type" in errors
    end

    test "returns 400 when message is missing" do
      conn = post_feedback(%{"type" => "bug"})

      assert conn.status == 400
      assert %{"error" => "Validation failed", "errors" => errors} = Jason.decode!(conn.resp_body)
      assert "Missing required field: message" in errors
    end

    test "returns 400 when type is invalid" do
      conn = post_feedback(%{"type" => "spam", "message" => "Buy now"})

      assert conn.status == 400
      assert %{"error" => "Validation failed", "errors" => errors} = Jason.decode!(conn.resp_body)
      assert "Invalid type: spam" in errors
    end

    test "returns 400 when an optional field has the wrong type" do
      conn =
        post_feedback(%{"type" => "bug", "message" => "Playback froze", "contact" => %{"x" => 1}})

      assert conn.status == 400
      assert %{"error" => "Validation failed", "errors" => errors} = Jason.decode!(conn.resp_body)
      assert "Invalid field: contact" in errors
    end

    test "returns 400 with a distinct body when message is too long" do
      conn = post_feedback(%{"type" => "bug", "message" => String.duplicate("a", 4097)})

      assert conn.status == 400

      assert %{"error" => "Message too long", "limit_bytes" => 4096} =
               Jason.decode!(conn.resp_body)
    end

    test "accepts omitted optional fields and ignores unknown fields" do
      conn =
        post_feedback(%{
          "type" => "question",
          "message" => "How does this work?",
          "extra_field" => "ignored"
        })

      assert conn.status == 201
      assert %{"id" => id} = Jason.decode!(conn.resp_body)

      submission = Feedback.get_submission!(id)
      assert submission.contact == nil
      assert submission.instance_id == nil
      assert submission.mydia_version == nil
    end

    test "accepts null instance_id and rate-limits it under anonymous" do
      for i <- 1..5 do
        conn =
          post_feedback(%{"type" => "bug", "message" => "Message #{i}", "instance_id" => nil},
            forwarded_for: "203.0.113.#{i}"
          )

        assert conn.status == 201
      end

      conn =
        post_feedback(%{"type" => "bug", "message" => "Message 6", "instance_id" => nil},
          forwarded_for: "203.0.113.6"
        )

      assert conn.status == 429
      assert ["3600"] = Plug.Conn.get_resp_header(conn, "retry-after")

      assert 5 == Repo.aggregate(Submission, :count, :id)
    end

    test "rate limits the sixth request from one IP" do
      for i <- 1..5 do
        conn =
          post_feedback(%{
            "type" => "bug",
            "message" => "Message #{i}",
            "instance_id" => "instance-#{i}"
          })

        assert conn.status == 201
      end

      conn =
        post_feedback(%{
          "type" => "bug",
          "message" => "Message 6",
          "instance_id" => "instance-6"
        })

      assert conn.status == 429
      assert %{"error" => "Too many requests"} = Jason.decode!(conn.resp_body)
      assert ["3600"] = Plug.Conn.get_resp_header(conn, "retry-after")
      assert 5 == Repo.aggregate(Submission, :count, :id)
    end

    test "rate limits the sixth request for one instance from different IPs" do
      for i <- 1..5 do
        conn =
          post_feedback(%{"type" => "idea", "message" => "Message #{i}", "instance_id" => "same"},
            forwarded_for: "198.51.100.#{i}"
          )

        assert conn.status == 201
      end

      conn =
        post_feedback(%{"type" => "idea", "message" => "Message 6", "instance_id" => "same"},
          forwarded_for: "198.51.100.6"
        )

      assert conn.status == 429
      assert 5 == Repo.aggregate(Submission, :count, :id)
    end
  end

  defp post_feedback(body, opts \\ []) do
    conn =
      Plug.Test.conn(:post, "/feedback", body)
      |> Plug.Conn.put_req_header("content-type", "application/json")

    conn =
      case Keyword.get(opts, :forwarded_for) do
        nil -> conn
        ip -> Plug.Conn.put_req_header(conn, "x-forwarded-for", ip)
      end

    conn
    |> Plug.Parsers.call(Plug.Parsers.init(parsers: [:json], json_decoder: Jason))
    |> Router.call([])
  end
end
