#!/bin/bash
cd "$(dirname "$0")"

# Load environment variables
export $(grep -v '^#' .env | xargs)
export DEBUG=1

echo "Testing huly_list_projects with debug logging..."
echo ""

# Create a test JSON-RPC request for listing tools and calling a tool
cat > /tmp/test-request.jsonl << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"huly_list_projects","arguments":{}}}
EOF

# Run the server with the test input and capture stderr (where logs go)
.build/debug/huly-mcp < /tmp/test-request.jsonl 2>&1 | tee /tmp/huly-test-output.log

echo ""
echo "Output saved to /tmp/huly-test-output.log"
echo "You can view logs with: cat /tmp/huly-test-output.log"
