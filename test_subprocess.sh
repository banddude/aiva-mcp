#!/bin/bash

echo "Testing subprocess server management..."

# Test subprocess_list_servers
echo "1. Testing subprocess_list_servers..."
curl -X POST http://localhost:3001 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "subprocess_list_servers",
      "arguments": {}
    }
  }' | jq

echo -e "\n2. Testing subprocess_add_server..."
curl -X POST http://localhost:3001 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0", 
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "subprocess_add_server",
      "arguments": {
        "name": "playwright",
        "command": "npx",
        "arguments": ["@playwright/mcp@latest"],
        "enabled": false
      }
    }
  }' | jq

echo -e "\n3. Listing servers after addition..."
curl -X POST http://localhost:3001 \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call", 
    "params": {
      "name": "subprocess_list_servers",
      "arguments": {}
    }
  }' | jq