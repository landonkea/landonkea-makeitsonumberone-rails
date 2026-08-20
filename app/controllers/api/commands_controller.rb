module Api
  # This controller is the whole reason this backend exists: a client sends
  # us what the user said, we send that (plus the shared Star Trek computer
  # prompt and any earlier turns) to Claude, and we hand back Claude's reply
  # in the same shape every client already knows how to speak and act on.
  class CommandsController < ApplicationController
    # POST /api/command
    #
    # Expects JSON like {"transcript": "what's the capital of France",
    # "conversation_id": 12, "client_label": "desktop"}. Only "transcript"
    # is required — leaving out conversation_id starts a brand new
    # conversation, and client_label is just a label for whoever's asking.
    def create
      transcript = command_params[:transcript].to_s.strip

      # An empty transcript means speech-to-text on the client produced
      # nothing usable — there's nothing worth sending to Claude, so bail
      # out with a clear 422 instead of spending an API call on blank text.
      if transcript.blank?
        render json: { error: "transcript is required" }, status: :unprocessable_content
        return
      end

      # Only look up an EXISTING conversation here — we deliberately hold
      # off creating a brand new one until we know the Claude call actually
      # succeeds, a few lines down. That way a failed request doesn't
      # litter the database with empty, message-less conversations.
      conversation = existing_conversation
      history = conversation ? conversation.recent_history : []

      begin
        result = ClaudeService.new.call(transcript, history: history)
      rescue ClaudeService::ClaudeError => e
        # 502 Bad Gateway is the right status here — WE are fine, it's the
        # upstream service (Claude) that failed, same idea as a reverse
        # proxy reporting its backend is unreachable.
        render json: { error: e.message }, status: :bad_gateway
        return
      end

      # Now that we know Claude answered, it's safe to create a fresh
      # conversation (if this was the first turn) and save both sides of
      # the exchange. Saving a user message but never getting a reply would
      # otherwise leave a conversation permanently one-sided.
      conversation ||= Conversation.create!(client_label: command_params[:client_label])
      conversation.messages.create!(role: "user", content: transcript)
      conversation.messages.create!(role: "assistant", content: result[:spoken_text])

      render json: {
        conversation_id: conversation.id,
        response: result[:spoken_text],
        actions: result[:actions]
      }, status: :ok
    end

    private

    # Whitelists exactly the params we accept from a client, same purpose
    # as Rails' usual strong-parameters pattern: a request can't sneak
    # extra fields (like trying to set a conversation's id directly) past
    # this controller.
    def command_params
      params.permit(:transcript, :conversation_id, :client_label)
    end

    # Looks up the conversation a client is asking to continue, if any. A
    # conversation_id that doesn't match anything falls back to nil (which
    # the caller treats as "start fresh") rather than raising a 404 — a
    # client restarting after this database was reset shouldn't be stuck
    # unable to talk to the assistant at all.
    def existing_conversation
      return nil if command_params[:conversation_id].blank?

      Conversation.find_by(id: command_params[:conversation_id])
    end
  end
end
