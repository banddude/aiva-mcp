#!/bin/bash

echo "Testing MCP fix with tool call..."
echo "================================="

# Get a fresh session ID first
echo "1. Getting fresh session..."
SESSION_RESPONSE=$(curl -s -D /tmp/session_headers.txt -X POST "https://officeadmin.io/mcp/qb/messages" \
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

SESSION_ID=$(grep -i "mcp-session-id:" /tmp/session_headers.txt | cut -d' ' -f2 | tr -d '\r\n')
echo "Session ID: $SESSION_ID"

# Send initialized
echo "2. Sending initialized..."
curl -s -X POST "https://officeadmin.io/mcp/qb/messages" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "method": "initialized"
  }' > /dev/null

# Test tool call and extract just the result structure for analysis
echo "3. Testing tool call response format..."
RESPONSE=$(curl -s -X POST "https://officeadmin.io/mcp/qb/messages" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "mcp-session-id: $SESSION_ID" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "Get_All_Customers",
      "arguments": {}
    }
  }')

echo "Full response structure analysis:"
echo "==================================="
echo "$RESPONSE" | grep "data: " | sed 's/data: //' | jq '.result | keys'
echo ""

echo "Content array analysis:"
echo "======================="
echo "$RESPONSE" | grep "data: " | sed 's/data: //' | jq '.result.content[0] | keys'
echo ""

echo "First 200 chars of actual text content:"
echo "========================================"
echo "$RESPONSE" | grep "data: " | sed 's/data: //' | jq -r '.result.content[0].text' | head -c 200
echo ""
echo ""

# Cleanup
rm -f /tmp/session_headers.txt
echo "Analysis complete!"