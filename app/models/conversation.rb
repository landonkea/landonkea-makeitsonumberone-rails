class Conversation < ApplicationRecord
  # One conversation can have many messages, and if we ever delete a
  # conversation we want its messages gone too, not left behind as orphan
  # rows, so `dependent: :destroy` deletes them automatically.
  has_many :messages, dependent: :destroy

  # The desktop client keeps only the most recent 20 entries of conversation
  # history (10 back-and-forth exchanges) before trimming older ones, see
  # make_it_so.py's `conversation_history[-20:]`. We copy that same number
  # here so a long-running conversation doesn't grow the Claude request
  # (and its cost) without bound.
  MAX_HISTORY_MESSAGES = 20

  # Returns the most recent messages, oldest-first, in the exact shape
  # Claude's Messages API wants: an array of {role:, content:} hashes. Oldest-
  # first matters — Claude reads the list as a literal transcript in order,
  # so if we got this backwards the conversation would look inside out.
  def recent_history
    messages
      .order(created_at: :desc, id: :desc)   # newest rows first (id as tiebreaker for same-timestamp rows), so LIMIT below keeps the newest ones...
      .limit(MAX_HISTORY_MESSAGES)
      .to_a
      .reverse                    # ...then flip back to oldest-first for Claude.
      .map { |message| { role: message.role, content: message.content } }
  end
end
