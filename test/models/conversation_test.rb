require "test_helper"

class ConversationTest < ActiveSupport::TestCase
  test "recent_history returns messages oldest-first in Claude's role/content shape" do
    conversation = conversations(:from_desktop)

    # The fixture file sets these three messages up with created_at times
    # 3, 2, and 1 minutes ago respectively, so this is the order Claude
    # needs to see them in to make sense of the conversation.
    expected = [
      { role: "user", content: "Computer, what time is it?" },
      { role: "assistant", content: "RESPONSE: It is 1400 hours, Captain.\n\nACTIONS:" },
      { role: "user", content: "Computer, open a web search for Ruby on Rails." }
    ]

    assert_equal expected, conversation.recent_history
  end

  test "recent_history only keeps the most recent MAX_HISTORY_MESSAGES entries" do
    conversation = conversations(:from_ios)

    # Create one more than the cap, oldest to newest, so we can check the
    # very oldest one gets dropped and everything after it survives.
    (Conversation::MAX_HISTORY_MESSAGES + 1).times do |i|
      conversation.messages.create!(role: "user", content: "message #{i}")
    end

    history = conversation.recent_history

    assert_equal Conversation::MAX_HISTORY_MESSAGES, history.length
    assert_equal "message 1", history.first[:content]
    assert_equal "message #{Conversation::MAX_HISTORY_MESSAGES}", history.last[:content]
  end

  test "destroying a conversation destroys its messages too" do
    conversation = conversations(:from_desktop)
    message_ids = conversation.messages.pluck(:id)

    conversation.destroy

    message_ids.each do |id|
      assert_nil Message.find_by(id: id)
    end
  end
end
