# Mirai

Mirai (未来) is a distributed AI agent platform based on Elixir/OTP.

## Running Mirai (First-Time Setup)

Mirai comes with an interactive CLI Wizard to configure your Authentication, API Keys, and networking gracefully without touching text tags manually.

**Step 1: Run the Interactive Setup Wizard**
Using Docker, spin up the setup wizard. This will securely create your `./data/.env` and `./data/config.yml` templates.
```bash
docker run -it --rm -v $(pwd):/app -w /app elixir:1.16 sh -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix mirai.setup"
```

**Step 2: Start the Server natively**
Once the wizard finishes and generates the `./data` directory configs, use the provided `docker-compose.yml` file to turn the engine on.
```bash
docker-compose up
```
*Note: Mirai will not boot if the initial data setup is completely missing!*

## Features Complete
* AgentMesh Distributed Architecture (Phase 1-4)
* Persistent Sessions & Histories via `sys_workspace`
* LLM Tool Calling Engine (`sys_read_file`, `sys_write_file`, `sys_execute_command`)
* LiveView Cluster Dashboard Analytics (`http://localhost:4000`)
* OpenRouter API Integration (`anthropic/claude-3-5-sonnet:beta` fallback)
* Console Onboarding Wizard (`mix mirai.setup`)
* Persistent Runtime YAML Configurations (`data/config.yml`)

## Running Unit Tests
Mirai ships with a `Bypass` HTTP mocking test suite to ensure the LLM integration layer behaves reliably without draining API credits.
```bash
docker run -it --rm -v $(pwd):/app -w /app elixir:1.16 sh -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

To interact with your system: 
1. Connect a Telegram Bot using `@BotFather`.
2. Generate your configs via `mix mirai.setup`.
3. Start the node (`docker-compose up`).
4. Send a Telegram message! The Mirai Agent Loop will automatically orchestrate the AI.
