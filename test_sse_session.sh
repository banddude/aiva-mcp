#!/bin/bash

SERVER_BASE="https://officeadmin.io/mcp/qb"
MESSAGES_URL="${SERVER_BASE}/messages"

echo "Testing MCP with session persistence..."
echo "================================================"

# Create a cookie jar for session persistence
COOKIE_JAR=$(mktemp)

# Step 1: Initialize session with cookie persistence
echo "1. Initializing with session cookies..."
INIT_RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -D /tmp/headers.txt -X POST "$MESSAGES_URL" \
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

echo "Response headers:"
cat /tmp/headers.txt | grep -i -E "(session|cookie|mcp)"
echo ""
echo "Response body:"
echo "$INIT_RESPONSE"
echo ""

# Step 2: Send initialized notification with cookies
echo "2. Sending initialized notification with session..."
NOTIFY_RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialized"
  }')

echo "Notify response:"
echo "$NOTIFY_RESPONSE"
echo ""

# Step 3: List tools with session
echo "3. Listing tools with session..."
TOOLS_RESPONSE=$(curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" -X POST "$MESSAGES_URL" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
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
rm -f "$COOKIE_JAR" /tmp/headers.txt
echo "Test complete!"
