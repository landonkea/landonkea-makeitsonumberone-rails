# A Message is one turn inside a Conversation — either something the user said
# (role "user") or something Claude replied (role "assistant"). Storing these
# as rows, instead of one big text blob, is what lets us cheaply grab "the last
# 20" for context without re-parsing anything.
class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      # Every message belongs to exactly one conversation. `null: false` means
      # the database itself refuses to save a message that isn't attached to
      # one, and `foreign_key: true` adds a real foreign-key constraint so an
      # orphaned message (pointing at a conversation that doesn't exist) is
      # impossible, not just unlikely.
      t.references :conversation, null: false, foreign_key: true

      # "user" or "assistant" — mirrors the role field Claude's Messages API
      # itself expects, so building the API request later is just reading
      # these columns straight across.
      t.string :role

      # The actual text of what was said. `text` (not `string`) because a
      # spoken transcript or a Claude reply can run much longer than a normal
      # varchar column comfortably holds.
      t.text :content

      t.timestamps
    end
  end
end
