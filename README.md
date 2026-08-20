# landonkea-makeitsonumberone-rails

A small Ruby on Rails backend for the "Make It So" voice assistant. If you've never coded before, this file explains what it does and how to get it running on your own machine.

## What is "Make It So"?

Landon built a voice assistant with the wake word "Computer" — say it, hear the Star Trek chime, ask for something, and it talks back like the computer from the USS Enterprise. It exists as three separate apps today, living in `landonkea-makeItSoNumberOne`:

- a Python desktop app
- an Android app (Kotlin)
- an iOS app (Swift)

Each one currently does the exact same five things on its own: listen for "Computer," record your voice, turn that recording into text, send the text to Claude (Anthropic's AI) with instructions on how to act like the Enterprise computer, and speak the reply back out loud. That last part — sending text to Claude and getting a reply — is copy-pasted into all three apps, each with its own copy of the Anthropic API key.

This repo pulls just that one piece out into a shared server. Instead of three apps each knowing how to talk to Claude, they can all send a plain HTTP request here and get the same reply back.

## What stays on your device and what moves to the server

Listening for the wake word, recording audio, converting speech to text, and speaking the reply out loud all *have* to stay on your phone or computer — a server somewhere on the internet has no access to your microphone or speakers. Those parts of the three apps are untouched by this project.

What this server takes over is the piece in the middle: given a line of text (what you said, already converted from speech), it sends that to Claude along with the same "you are the Enterprise computer" instructions the desktop app uses, and hands back Claude's reply.

Claude can also ask for actions to be carried out — "open Safari," "search the web for X," "type this text." Those are all things that only make sense to run on the device that's sitting in front of the user, so this server never tries to execute them itself. It just passes each action back to whichever app asked, structured as JSON, and it's up to that app to actually do it (exactly like the desktop app already does today with its own action router).

## The one endpoint

```
POST /api/command
```

Send it JSON like this:

```json
{
  "transcript": "Computer, what's the weather like?",
  "conversation_id": null,
  "client_label": "desktop"
}
```

- `transcript` — required. Whatever the user said, already converted to text by the client's own speech-to-text.
- `conversation_id` — optional. Leave it out (or send `null`) the first time; the response will include a `conversation_id` you can send back on the next request so Claude remembers what was already said. Without it, every request starts a brand new conversation with no memory of earlier turns.
- `client_label` — optional. Just a note for your own records ("desktop", "android", "ios") so it's easy to tell where a conversation came from later.

You get back:

```json
{
  "conversation_id": 7,
  "response": "It's currently 68 degrees and clear, Captain.",
  "actions": [
    { "action": "get_weather", "params": { "location": "current" } }
  ]
}
```

`response` is the line to speak out loud. `actions` is a list of things Claude thinks should happen on the device (can be empty).

## How it fits together

```
   Desktop app  ─┐
   Android app  ─┼─► POST /api/command ─► Claude Service ─► Anthropic's Claude API
   iOS app      ─┘         │                    │
                            │                    └─► same system prompt as
                            │                        shared/prompts/system_prompt.txt
                            ▼
                    saves the exchange to
                    a SQLite database so
                    the next request can
                    include prior context
```

The system prompt lives at `lib/shared_prompts/system_prompt.txt` — it's a byte-for-byte copy of the same file the original three apps already use, so this backend has the exact same Star Trek computer personality, not a reworded version of it.

## Running it locally

You'll need Ruby 3.4.9 installed (check with `ruby -v`).

1. Clone this repo and move into it.
2. Install the gems: `bundle install`
3. Copy the example environment file: `cp .env.example .env`
4. Open `.env` and put a real Anthropic API key in it (get one at [console.anthropic.com](https://console.anthropic.com/)). Nothing works without this — every request will fail with a clear error telling you the key is missing until you add one.
5. Set up the database: `bin/rails db:prepare`
6. Start the server: `bin/rails server`
7. Try it:
   ```
   curl -X POST http://localhost:3000/api/command \
     -H "Content-Type: application/json" \
     -d '{"transcript": "Computer, hello."}'
   ```

## Running the tests

```
bin/rails test
```

The tests never make a real call to Anthropic's API (and never spend any real API credits) — they use a tool called WebMock to intercept the outbound request and hand back a fake, realistic Claude reply instead. That's also why the tests don't need a real API key to pass.

## Environment variables

See `.env.example` for the full list. The short version:

- `ANTHROPIC_API_KEY` — required. Your Anthropic API key.
- `ANTHROPIC_MODEL` — optional. Which Claude model to call. Defaults to the same one the desktop app uses if you don't set it.

## Running it in Docker

Rails generates a production-ready `Dockerfile` for you automatically, and it works out of the box:

```
docker build -t makeitsonumberone-rails .
docker run -d -p 80:80 \
  -e RAILS_MASTER_KEY=$(cat config/master.key) \
  -e ANTHROPIC_API_KEY=your-key-here \
  makeitsonumberone-rails
```

## What's where

- `app/controllers/api/commands_controller.rb` — the `POST /api/command` endpoint itself.
- `app/services/claude_service.rb` — builds the request to Claude, sends it, and parses the reply into spoken text plus a list of actions.
- `app/models/conversation.rb` and `app/models/message.rb` — how conversation history gets saved and looked back up.
- `lib/shared_prompts/system_prompt.txt` — the shared Star Trek computer personality, copied verbatim from the original monorepo.
- `test/` — Minitest tests for all of the above.

## A note on fidelity to the original apps

The desktop app's Python code (`core/ai.py`) appends its own extra instructions to the shared prompt telling Claude to reply in strict JSON instead of the plain text format the shared prompt describes, plus seven extra desktop-only actions like `sleep_mode` and `get_weather` that depend on files and integrations only the desktop app has installed. Those additions are desktop-specific, not part of the shared prompt, so this server sends the shared prompt exactly as written and parses the plain "RESPONSE: ... ACTIONS: ..." text format it describes — the same format the shared prompt actually asks for, and the one Android and iOS are built to expect too.
