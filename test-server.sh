#!/bin/bash
cd "$(dirname "$0")"

# Load environment variables
export $(grep -v '^#' .env | xargs)
export DEBUG=1

echo "🔨 Building huly-mcp (debug mode)..."
swift build

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "🚀 Starting MCP Server in test mode..."
echo "📍 URL: $HULY_URL"
echo "👤 User: $HULY_EMAIL"
echo "🏢 Workspace: $HULY_WORKSPACE"
echo "🐛 Debug logs: ENABLED"
echo ""

# Test by running the server and sending it a tool call request
# Use npx to test with a simple MCP client
npx -y @modelcontextprotocol/inspector .build/debug/huly-mcp 2>&1 | tee /tmp/huly-mcp-test.log
