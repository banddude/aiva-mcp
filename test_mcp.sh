#!/bin/bash

# Test script for MCP Streamable HTTP implementation
# Usage: ./test_mcp.sh <mcp_server_url>

SERVER_URL="${1:-http://localhost:8000/mcp}"

echo "Testing MCP server at: $SERVER_URL"
echo "================================================"

# Step 1: Initialize session
echo "1. Initializing MCP session..."
INIT_RESPONSE=$(curl -s -w "HTTPCODE:%{http_code}\nHEADERS:%{header_json}\n" -X POST "$SERVER_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "MCP-Protocol-Version: 2025-03-26" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": {
      "protocolVersion": "2025-03-26",
      "capabilities": {
        "tools": {}
      },
      "clientInfo": {
        "name": "test-client",
        "version": "1.0.0"
      }
    }
  }')

echo "Initialize response:"
echo "$INIT_RESPONSE"
echo ""

# Extract session ID if present (simplified - would need proper JSON parsing)
SESSION_ID=$(echo "$INIT_RESPONSE" | grep -o '"Mcp-Session-Id":"[^"]*"' | cut -d'"' -f4 || echo "")

if [ -n "$SESSION_ID" ]; then
  echo "Session ID extracted: $SESSION_ID"
  SESSION_HEADER="-H \"Mcp-Session-Id: $SESSION_ID\""
else
  echo "No session ID found in response"
  SESSION_HEADER=""
fi

# Step 2: Send initialized notification
echo "2. Sending initialized notification..."
if [ -n "$SESSION_ID" ]; then
  curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -H "Mcp-Session-Id: $SESSION_ID" \
    -d '{
      "jsonrpc": "2.0",
      "method": "initialized"
    }'
fi
echo ""

# Step 3: List tools
echo "3. Listing available tools..."
if [ -n "$SESSION_ID" ]; then
  curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -H "Mcp-Session-Id: $SESSION_ID" \
    -d '{
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/list",
      "params": {}
    }'
else
  curl -s -X POST "$SERVER_URL" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json, text/event-stream" \
    -d '{
      "jsonrpc": "2.0",
      "id": 2,
      "method": "tools/list",
      "params": {}
    }'
fi
echo ""
echo "Test complete!"
