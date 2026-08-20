require "test_helper"

module Api
  class CommandsControllerTest < ActionDispatch::IntegrationTest
    # The controller reads ANTHROPIC_API_KEY straight from ENV by default
    # (see ClaudeService#initialize), so tests need a fake one present —
    # we set it here and put the original value back afterward so this
    # test can't leak state into any test that runs after it.
    setup do
      @original_api_key = ENV["ANTHROPIC_API_KEY"]
      ENV["ANTHROPIC_API_KEY"] = "test-key"
    end

    teardown do
      ENV["ANTHROPIC_API_KEY"] = @original_api_key
    end

    def stub_claude_reply(reply_text)
      body = {
        id: "msg_test123",
        type: "message",
        role: "assistant",
        model: "claude-sonnet-4-20250514",
        content: [ { type: "text", text: reply_text } ],
        stop_reason: "end_turn",
        stop_sequence: nil,
        usage: { input_tokens: 10, output_tokens: 10 }
      }.to_json

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })
    end

    test "creates a new conversation, saves both turns, and returns Claude's reply" do
      stub_claude_reply("RESPONSE: Course laid in.\n\nACTIONS:\n- action: open_app\n  params:\n    name: Maps")

      assert_difference "Conversation.count", 1 do
        assert_difference "Message.count", 2 do
          post "/api/command", params: { transcript: "Computer, set a course for Risa.", client_label: "desktop" }, as: :json
        end
      end

      assert_response :success
      json = JSON.parse(response.body)

      assert json["conversation_id"].present?
      assert_equal "Course laid in.", json["response"]
      assert_equal [ { "action" => "open_app", "params" => { "name" => "Maps" } } ], json["actions"]

      conversation = Conversation.find(json["conversation_id"])
      assert_equal "desktop", conversation.client_label
      assert_equal 2, conversation.messages.count
      assert_equal [ "user", "assistant" ], conversation.messages.order(:created_at).pluck(:role)
    end

    test "reuses an existing conversation and forwards its prior turns to Claude" do
      conversation = conversations(:from_desktop)
      captured_request = nil

      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .with { |request| captured_request = request; true }
        .to_return(
          status: 200,
          body: {
            id: "msg_test456", type: "message", role: "assistant",
            model: "claude-sonnet-4-20250514",
            content: [ { type: "text", text: "RESPONSE: Understood.\n\nACTIONS:" } ],
            stop_reason: "end_turn", stop_sequence: nil,
            usage: { input_tokens: 5, output_tokens: 5 }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      post "/api/command",
        params: { transcript: "Computer, one more thing.", conversation_id: conversation.id },
        as: :json

      assert_response :success
      json = JSON.parse(response.body)
      assert_equal conversation.id, json["conversation_id"]

      sent_messages = JSON.parse(captured_request.body)["messages"]
      # The fixture conversation already has 3 turns (see
      # test/fixtures/messages.yml), plus this request's brand new one.
      assert_equal 4, sent_messages.length
      assert_equal "Computer, one more thing.", sent_messages.last["content"]
    end

    test "returns 422 when transcript is blank" do
      post "/api/command", params: { transcript: "   " }, as: :json

      assert_response :unprocessable_content
      assert JSON.parse(response.body)["error"].present?
      assert_not_requested :post, "https://api.anthropic.com/v1/messages"
    end

    test "returns 502 and saves nothing when the Claude API call fails" do
      stub_request(:post, "https://api.anthropic.com/v1/messages")
        .to_return(status: 500, body: { type: "error", error: { type: "api_error", message: "boom" } }.to_json)

      assert_no_difference [ "Conversation.count", "Message.count" ] do
        post "/api/command", params: { transcript: "Computer, hello." }, as: :json
      end

      assert_response :bad_gateway
      assert JSON.parse(response.body)["error"].present?
    end
  end
end
