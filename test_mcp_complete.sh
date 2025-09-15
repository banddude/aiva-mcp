#!/bin/bash

SERVER_BASE="https://officeadmin.io/mcp/qb"
MESSAGES_URL="${SERVER_BASE}/messages"

echo "Testing complete MCP flow at: $MESSAGES_URL"
echo "================================================"

# Step 1: Initialize session
echo "1. Initializing MCP session..."
INIT_RESPONSE=$(curl -s -X POST "$MESSAGES_URL" \
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
        "name": "AIVA",
        "version": "1.0.0"
      }
    }
  }')

echo "Initialize response:"
echo "$INIT_RESPONSE" | jq . 2>/dev/null || echo "$INIT_RESPONSE"
echo ""

# Step 2: Send initialized notification
echo "2. Sending initialized notification..."
curl -s -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialized"
  }' | jq . 2>/dev/null || echo "Response: $?"
echo ""

# Step 3: List tools
echo "3. Listing available tools..."
TOOLS_RESPONSE=$(curl -s -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }')

echo "Tools response:"
echo "$TOOLS_RESPONSE" | jq . 2>/dev/null || echo "$TOOLS_RESPONSE"
echo ""
echo "Test complete!"
