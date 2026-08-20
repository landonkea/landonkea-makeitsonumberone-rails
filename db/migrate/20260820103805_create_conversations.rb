# A Conversation is one ongoing back-and-forth with a client (the desktop app,
# the Android app, or the iOS app). We keep a row for it so the same client can
# send us its conversation_id on the next request and Claude will remember what
# was already said, the same way the desktop app currently does by saving
# conversation_history.json to disk between runs.
class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    # `change` is Rails' "describe the end state, I'll figure out up and down
    # myself" migration style — for a plain create_table like this one, that's
    # all we need.
    create_table :conversations do |t|
      # Which client started this conversation ("desktop", "android", "ios").
      # Optional — nothing stops a request from omitting it — but handy for
      # debugging when you're staring at a database full of rows and want to
      # know which app they came from.
      t.string :client_label

      # Rails shorthand for adding both created_at and updated_at columns,
      # kept automatically in sync on every save.
      t.timestamps
    end
  end
end
