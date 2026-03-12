# test_cluster/integration_test.exs
# This script is run by a temporary elixir process that connects to alpha.
# Usage: docker exec mirai_alpha elixir --sname tester --cookie mirai_cluster_test test_cluster/integration_test.exs

ExUnit.start(trace: true)

defmodule Mirai.ClusterIntegrationTest do
  use ExUnit.Case, async: false

  @alpha_node :"mirai@alpha"
  @beta_node :"mirai@beta"

  setup_all do
    # The application is already running in background nodes.
    # Connect this test script to the alpha node.
    assert Node.connect(@alpha_node) == true, "Tester failed to connect to Alpha: #{@alpha_node}"
    
    # Instruct Alpha to connect to Beta
    :rpc.call(@alpha_node, Node, :connect, [@beta_node])
    
    Process.sleep(500)
    :ok
  end

  test "Node.list/0 on Alpha sees Beta" do
    node_list = :rpc.call(@alpha_node, Node, :list, [])
    assert @beta_node in node_list
  end

  test ":rpc.call from Alpha to Beta Node.self/0" do
    # Alpha calls Beta
    result = :rpc.call(@alpha_node, :rpc, :call, [@beta_node, Node, :self, []])
    assert result == @beta_node
  end

  test "NodeRegistry RPC calls work" do
    result = :rpc.call(@alpha_node, :rpc, :call, [@beta_node, Mirai.Dashboard.NodeRegistry, :list_nodes, []])
    assert is_list(result)
    assert Enum.any?(result, fn node_data -> node_data.id == "local_mirai_1" end)
  end

  test "sessions_send tool successfully dispatches message from alpha down to beta" do
    test_agent_id = "test_target_exunit"
    
    # Execute tool on Alpha
    {:ok, msg} = :rpc.call(@alpha_node, Mirai.Tools.SessionsSend, :execute, [
      %{"to_agent_id" => test_agent_id, "payload" => "Hello across the cluster!", "node" => "mirai@beta"}, 
      %{agent_id: "test_sender", session_id: "test_session_1"}
    ])
    
    assert msg =~ "dispatched to #{test_agent_id}"

    # Give PubSub time to process
    Process.sleep(1500)

    target_session_key = "agent:#{test_agent_id}:mesh:direct:global"
    
    # Verify the session was spawned on Beta
    result = :rpc.call(@alpha_node, :rpc, :call, [@beta_node, Registry, :lookup, [Mirai.Tools.Registry, {:session, target_session_key}]])
    
    case result do
      [{_pid, _}] -> 
        assert true
      other -> 
        flunk("Beta did not spawn the session (got: #{inspect(other)})")
    end
  end
end
