# This is the one piece of the whole "Make It So" idea that's actually
# shared infrastructure rather than something tied to a specific device's
# mic and speakers: turning a transcript into a Claude reply, using the
# exact same Star Trek computer personality every client already uses.
#
# Everything upstream of this (wake word detection, recording your voice,
# converting speech to text) and everything downstream (speaking the reply
# out loud, actually opening an app on YOUR OWN machine) has to stay on the
# device that owns the microphone and speakers. This class is the part in
# the middle that any of those devices can now call over the network instead
# of each one embedding its own Anthropic API key and prompt logic.
class ClaudeService
  # A small, specific error class so callers (the controller) can catch
  # exactly "something about talking to Claude went wrong" without also
  # accidentally swallowing unrelated bugs elsewhere in the request.
  class ClaudeError < StandardError; end

  # Where our copy of the shared system prompt lives inside this repo. It's
  # the exact same file as shared/prompts/system_prompt.txt in the original
  # landonkea-makeItSoNumberOne monorepo, copied over byte-for-byte, not
  # reworded, so every client (this Rails backend included) gets the same
  # Star Trek computer personality and is told to reply in the same
  # RESPONSE:/ACTIONS: text format.
  SYSTEM_PROMPT_PATH = Rails.root.join("lib", "shared_prompts", "system_prompt.txt")

  # Which Claude model to call. Defaults to the same model the desktop
  # client's core/ai.py uses today, but can be overridden via ENV so a
  # newer model doesn't need a code change and redeploy to adopt.
  MODEL = ENV.fetch("ANTHROPIC_MODEL", "claude-sonnet-4-20250514")

  # A ceiling on how long Claude's reply is allowed to be. Matches the
  # desktop client's own limit so replies stay short enough to comfortably
  # speak out loud rather than rambling.
  MAX_TOKENS = 1024

  # How "creative" vs. deterministic Claude's replies are — 0 is fully
  # deterministic, 1 is maximally varied. 0.7 matches the desktop client so
  # this backend's replies feel like the same assistant, not a different
  # one.
  TEMPERATURE = 0.7

  # Reads the prompt file once and keeps it in memory rather than re-reading
  # it from disk on every single request — the file never changes while the
  # server is running, so there's nothing to gain from reading it twice.
  def self.system_prompt
    @system_prompt ||= File.read(SYSTEM_PROMPT_PATH)
  end

  # `api_key:` defaults to whatever's in the ANTHROPIC_API_KEY environment
  # variable, but accepting it as a constructor argument too means a test
  # can inject a fake key without having to stub real ENV state.
  def initialize(api_key: ENV["ANTHROPIC_API_KEY"])
    @api_key = api_key
  end

  # The main entry point: given what the user said (`transcript`) and the
  # earlier turns of this conversation (`history`, oldest-first, already
  # shaped as {role:, content:} hashes), ask Claude for a reply and hand
  # back {spoken_text:, actions:}.
  def call(transcript, history: [])
    # Fail fast and clearly if nobody configured an API key, rather than
    # letting the Anthropic client raise a more cryptic error further down
    # the line.
    raise ClaudeError, "ANTHROPIC_API_KEY is not set" if @api_key.blank?

    # Build the Anthropic client fresh for this call (it's cheap to
    # construct) instead of caching one on the class, so a per-instance
    # api_key override always takes effect instead of a stale cached client
    # silently reusing an old key.
    client = Anthropic::Client.new(api_key: @api_key)

    # Claude's Messages API wants the WHOLE conversation as one ordered
    # list — earlier turns plus the brand new thing the user just said. It
    # has no separate concept of "history" versus "the current message."
    messages = history + [ { role: "user", content: transcript } ]

    begin
      response = client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system: self.class.system_prompt,
        temperature: TEMPERATURE,
        messages: messages
      )
    rescue Anthropic::Errors::APIError => e
      # Wrap every flavor of Anthropic error (network failure, bad API key,
      # rate limiting, a 500 from Anthropic's own servers) into our own
      # error type, so the controller only ever has to rescue one thing.
      raise ClaudeError, "Claude API request failed: #{e.message}"
    end

    parse_response(extract_text(response))
  end

  private

  # Pulls the plain-text reply out of Claude's response. A message's
  # content is an ARRAY of blocks (Claude can mix text, tool-use, etc. in
  # one reply), so we scan for the first block whose type is text and use
  # that — mirrors desktop's _extract_claude_text().
  def extract_text(response)
    text_block = response.content.find { |block| block.type == :text }
    text_block ? text_block.text : ""
  end

  # Splits Claude's raw reply into the part meant to be spoken out loud and
  # the list of structured actions to hand back to whichever client asked.
  # This is a Ruby port of desktop's _parse_response_legacy() /
  # _parse_actions_legacy(): the shared system prompt (copied verbatim
  # above) tells Claude to answer in the "RESPONSE: ... ACTIONS: ..." text
  # layout, so that's the format we parse here — not desktop's own JSON
  # addendum, which is a desktop-only override and isn't part of the
  # shared prompt file itself.
  def parse_response(full_text)
    {
      spoken_text: extract_spoken_text(full_text),
      actions: extract_actions(full_text)
    }
  end

  # Grabs everything between "RESPONSE:" and either "ACTIONS:" or the end
  # of the string. The `m` flag makes `.` match newlines too, since a
  # spoken reply can legitimately span more than one line.
  def extract_spoken_text(full_text)
    match = full_text.match(/RESPONSE:\s*(.+?)(?=\n\s*ACTIONS:|\z)/m)
    match ? match[1].strip : ""
  end

  # Grabs everything after "ACTIONS:" and hands it off to be broken up into
  # individual action entries.
  def extract_actions(full_text)
    match = full_text.match(/ACTIONS:\s*(.+)/m)
    return [] unless match

    split_into_action_blocks(match[1].strip)
  end

  # Breaks the ACTIONS section into one chunk per "- action: <name>" list
  # item. The split pattern matches either the very start of the string or
  # a newline, immediately followed by "- action:", so the FIRST action in
  # the list splits off correctly too — desktop's own git history has a
  # real bug where an off-by-one here silently dropped the first action of
  # every response, this pattern is written specifically to avoid that.
  def split_into_action_blocks(actions_text)
    blocks = actions_text.split(/(?:\A|\n)\s*-\s+action:/)
    blocks.filter_map { |block| parse_action_block(block) }
  end

  # Parses one action chunk (its name, plus an optional "params:" section)
  # into {action:, params:}. Returns nil for a blank chunk, which happens
  # for the leading fragment before the very first "- action:" that
  # String#split always produces.
  def parse_action_block(block)
    block = block.strip
    return nil if block.empty?

    action_name = block.lines.first.to_s.strip
    { action: action_name, params: parse_action_params(block) }
  end

  # Pulls the "key: value" lines out of a single action's "params:"
  # section into a plain hash. Values stay as plain strings here, just
  # like desktop's legacy parser — Claude is a language model, not a
  # strictly typed API, so a param value like "amount: 3" arrives as the
  # string "3", and it's each action's own responsibility (on whichever
  # client actually runs it) to convert that to whatever type it needs.
  def parse_action_params(block)
    params_match = block.match(/params:\s*(.+)/m)
    return {} unless params_match

    params_match[1].strip.lines.each_with_object({}) do |line, params|
      line = line.strip
      next unless line.include?(":")

      key, value = line.split(":", 2)
      params[key.strip] = value.strip
    end
  end
end
