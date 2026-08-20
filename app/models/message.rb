class Message < ApplicationRecord
  # Every message has to point back at the conversation it's part of —
  # Rails enforces this at save time (in addition to the database-level
  # foreign key from the migration).
  belongs_to :conversation

  # Claude's API only understands two roles in a message list, so we refuse
  # to save anything else. Catching a typo here, at save time, is a lot
  # friendlier than it silently reaching the Claude API and getting rejected
  # there instead.
  validates :role, inclusion: { in: %w[user assistant] }

  # An empty message isn't a real turn in the conversation — either the user
  # said something or Claude replied with something, so require actual text.
  validates :content, presence: true
end
