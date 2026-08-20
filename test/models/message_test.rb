require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "valid with role user or assistant and non-blank content" do
    message = Message.new(conversation: conversations(:from_desktop), role: "user", content: "hello")
    assert message.valid?
  end

  test "invalid with a role that isn't user or assistant" do
    message = Message.new(conversation: conversations(:from_desktop), role: "system", content: "hello")
    assert_not message.valid?
  end

  test "invalid with blank content" do
    message = Message.new(conversation: conversations(:from_desktop), role: "user", content: "")
    assert_not message.valid?
  end

  test "invalid without a conversation" do
    message = Message.new(role: "user", content: "hello")
    assert_not message.valid?
  end
end
