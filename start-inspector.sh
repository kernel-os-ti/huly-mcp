#!/bin/bash
cd "$(dirname "$0")"

# Load environment variables
export $(grep -v '^#' .env | xargs)

echo "🚀 Starting MCP Inspector..."
echo "📍 URL: $HULY_URL"
echo "👤 User: $HULY_EMAIL"
echo "🏢 Workspace: $HULY_WORKSPACE"
echo ""

mcp-inspector .build/release/huly-mcp
