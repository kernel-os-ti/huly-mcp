#!/bin/bash
cd "$(dirname "$0")"

# Load environment variables
export $(grep -v '^#' .env | xargs)

echo "🔨 Building huly-mcp (release mode)..."
swift build -c release

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "🚀 Starting MCP Server..."
echo "📍 URL: $HULY_URL"
echo "👤 User: $HULY_EMAIL"
echo "🏢 Workspace: $HULY_WORKSPACE"
echo "🐛 Debug logs: ENABLED (set DEBUG=0 to disable)"
echo ""

.build/release/huly-mcp
