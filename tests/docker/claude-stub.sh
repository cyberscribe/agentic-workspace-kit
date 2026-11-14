#!/bin/bash
# A stand-in for claude in the test containers: no network and no login. It answers the two commands the
# scheduler runs besides a session, and a session with the stream a real one starts with.
case "$1 $2" in
    "mcp list") echo "No MCP servers configured."; exit 0 ;;
    "auth status") echo '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"pro"}'; exit 0 ;;
    "--version ") echo "0.0.0 (stub)"; exit 0 ;;
esac
cat >/dev/null
echo '{"type":"system","subtype":"init","apiKeySource":"none","session_id":"stub"}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"OK","total_cost_usd":0.001}'
