#!/bin/bash

SERVER_BASE="https://officeadmin.io/mcp/qb"
MESSAGES_URL="${SERVER_BASE}/messages"

echo "Testing MCP with extracted session ID..."
echo "================================================"

# Step 1: Initialize and extract session ID
echo "1. Initializing and extracting session ID..."
SESSION_RESPONSE=$(curl -s -D /tmp/init_headers.txt -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
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

# Extract session ID from headers
SESSION_ID=$(grep -i "mcp-session-id:" /tmp/init_headers.txt | cut -d' ' -f2 | tr -d '\r\n')
echo "Extracted session ID: '$SESSION_ID'"
echo ""

# Step 2: Send initialized notification with session ID
echo "2. Sending initialized notification with session ID..."
NOTIFY_RESPONSE=$(curl -s -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialized"
  }')

echo "Notify response:"
echo "$NOTIFY_RESPONSE"
echo ""

# Step 3: List tools with session ID
echo "3. Listing tools with session ID..."
TOOLS_RESPONSE=$(curl -s -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": {}
  }')

echo "Tools response:"
echo "$TOOLS_RESPONSE"
echo ""

# Cleanup
rm -f /tmp/init_headers.txt
echo "Test complete!"
