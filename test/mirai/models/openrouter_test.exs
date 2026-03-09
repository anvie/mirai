defmodule Mirai.Models.OpenRouterTest do
  use ExUnit.Case, async: true
  alias Mirai.Models.OpenRouter

  setup do
    bypass = Bypass.open()
    {:ok, bypass: bypass}
  end

  test "returns standard text completion", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/v1/chat/completions", fn conn ->
      Plug.Conn.put_resp_content_type(conn, "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "choices" => [
          %{
            "message" => %{
              "content" => "Hello! This is a mock response from OpenRouter."
            }
          }
        ]
      }))
    end)

    url = "http://localhost:#{bypass.port}/api/v1/chat/completions"
    opts = [api_url: url, api_key: "fake", model: "fake-model"]
    messages = [%{role: "user", content: "Hello?"}]

    assert {:ok, result} = OpenRouter.chat_completion(messages, opts)

    assert [text_block] = result
    assert text_block["type"] == "text"
    assert text_block["text"] == "Hello! This is a mock response from OpenRouter."
  end

  test "returns tool invocation properly", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/v1/chat/completions", fn conn ->
      Plug.Conn.put_resp_content_type(conn, "application/json")
      |> Plug.Conn.resp(200, Jason.encode!(%{
        "choices" => [
          %{
            "message" => %{
              "content" => nil,
              "tool_calls" => [
                %{
                  "id" => "call_123456",
                  "type" => "function",
                  "function" => %{
                    "name" => "sys_write_file",
                    "arguments" => "{\"path\": \"test.txt\", \"content\": \"hello\"}"
                  }
                }
              ]
            }
          }
        ]
      }))
    end)

    url = "http://localhost:#{bypass.port}/api/v1/chat/completions"
    opts = [api_url: url, api_key: "fake", model: "fake-model"]
    messages = [%{role: "user", content: "Write a file"}]

    assert {:ok, result} = OpenRouter.chat_completion(messages, opts)

    assert [tool_block] = result
    assert tool_block["type"] == "tool_use"
    assert tool_block["name"] == "sys_write_file"
    assert tool_block["id"] == "call_123456"
    assert tool_block["input"]["path"] == "test.txt"
    assert tool_block["input"]["content"] == "hello"
  end

  test "handles 500 error gracefully", %{bypass: bypass} do
    Bypass.expect_once(bypass, "POST", "/api/v1/chat/completions", fn conn ->
      Plug.Conn.put_resp_content_type(conn, "application/json")
      |> Plug.Conn.resp(500, Jason.encode!(%{"error" => "Internal Server Error"}))
    end)

    url = "http://localhost:#{bypass.port}/api/v1/chat/completions"
    opts = [api_url: url, api_key: "fake", model: "fake-model"]
    messages = [%{role: "user", content: "Hello?"}]

    assert {:error, "API returned status 500"} = OpenRouter.chat_completion(messages, opts)
  end
end
