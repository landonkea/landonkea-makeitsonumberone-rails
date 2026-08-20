require "test_helper"

class ClaudeServiceTest < ActiveSupport::TestCase
  # A stand-in for what Anthropic's real API returns, shaped exactly like
  # https://docs.anthropic.com/en/api/messages describes: a "content" array
  # holding one text block with Claude's whole reply inside it, still in
  # the raw RESPONSE:/ACTIONS: text format our shared system prompt asks
  # for — parsing that text apart is ClaudeService's own job, not this
  # fixture's.
  def anthropic_success_body(reply_text)
    {
      id: "msg_test123",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-4-20250514",
      content: [ { type: "text", text: reply_text } ],
      stop_reason: "end_turn",
      stop_sequence: nil,
      usage: { input_tokens: 42, output_tokens: 17 }
    }.to_json
  end

  test "call parses spoken text and multiple actions out of Claude's reply" do
    reply_text = <<~TEXT
      RESPONSE: Opening Safari and searching the web for you now.

      ACTIONS:
      - action: open_app
        params:
          name: Safari
      - action: search_web
        params:
          query: ruby on rails tutorials
    TEXT

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: anthropic_success_body(reply_text), headers: { "Content-Type" => "application/json" })

    result = ClaudeService.new(api_key: "test-key").call("Computer, open Safari and search for Ruby on Rails.")

    assert_equal "Opening Safari and searching the web for you now.", result[:spoken_text]
    assert_equal(
      [
        { action: "open_app", params: { "name" => "Safari" } },
        { action: "search_web", params: { "query" => "ruby on rails tutorials" } }
      ],
      result[:actions]
    )
  end

  test "call sends the exact shared system prompt, the API key header, and history in order" do
    captured_request = nil

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with { |request| captured_request = request; true }
      .to_return(status: 200, body: anthropic_success_body("RESPONSE: Acknowledged.\n\nACTIONS:"), headers: { "Content-Type" => "application/json" })

    history = [
      { role: "user", content: "Computer, what is the stardate?" },
      { role: "assistant", content: "RESPONSE: Unable to compute.\n\nACTIONS:" }
    ]

    ClaudeService.new(api_key: "test-key").call("Computer, try again.", history: history)

    body = JSON.parse(captured_request.body)

    # The shared prompt has to be forwarded byte-for-byte — this backend's
    # whole job is NOT to invent its own version of the Star Trek computer
    # personality.
    assert_equal ClaudeService.system_prompt, body["system"]
    assert_equal "test-key", captured_request.headers["X-Api-Key"]

    # Earlier turns come first, the brand new thing the user just said
    # comes last — Claude reads this list as a literal transcript.
    assert_equal(
      [
        { "role" => "user", "content" => "Computer, what is the stardate?" },
        { "role" => "assistant", "content" => "RESPONSE: Unable to compute.\n\nACTIONS:" },
        { "role" => "user", "content" => "Computer, try again." }
      ],
      body["messages"]
    )
  end

  test "call returns an empty actions array when Claude's reply has none" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: anthropic_success_body("RESPONSE: You are welcome, Captain.\n\nACTIONS:"), headers: { "Content-Type" => "application/json" })

    result = ClaudeService.new(api_key: "test-key").call("Computer, thank you.")

    assert_equal "You are welcome, Captain.", result[:spoken_text]
    assert_equal [], result[:actions]
  end

  test "call raises ClaudeError instead of making a request when no API key is configured" do
    error = assert_raises(ClaudeService::ClaudeError) do
      ClaudeService.new(api_key: nil).call("Computer, hello.")
    end

    assert_match(/ANTHROPIC_API_KEY/, error.message)
    assert_not_requested :post, "https://api.anthropic.com/v1/messages"
  end

  test "call raises ClaudeError when Anthropic's API responds with an error status" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        status: 401,
        body: { type: "error", error: { type: "authentication_error", message: "invalid x-api-key" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert_raises(ClaudeService::ClaudeError) do
      ClaudeService.new(api_key: "bad-key").call("Computer, hello.")
    end
  end
end
