#!/dis/sh.dis
# Test tool_use flow through native llmsrv
load std

# Bootstrap services
mount -ac {mntgen} /n >[2] /dev/null
bind -a '#I' /net >[2] /dev/null
ndb/cs
auth/factotum

# Provision API key
factotumkey=`{os sh -c 'k=${ANTHROPIC_API_KEY:-$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw ~/Library/LaunchAgents/com.nervsystems.llm9p.plist 2>/dev/null)}; if [ -n "$k" ]; then echo "key proto=pass service=anthropic user=apikey !password=$k"; fi'}
echo $factotumkey > /mnt/factotum/ctl >[2] /dev/null

# Start llmsrv
llmsrv &
sleep 1

# Create tmp for debug output
mkdir -p /tmp >[2] /dev/null

# Create session and install a simple tool
id=`{cat /n/llm/new}
echo 'session:' $id

# Install a simple test tool
echo '[{"name":"greet","description":"Say hello to someone. Args: name","input_schema":{"type":"object","properties":{"args":{"type":"string"}},"required":["args"]}}]' > /n/llm/$id/tools
echo 'tools installed'

# Ask the LLM to use the tool
echo 'Use the greet tool to greet Alice.' > /n/llm/$id/ask
response=`{cat /n/llm/$id/ask}
echo 'step 1 response:' $response

# Check debug dump of step 1 request
echo '=== step 1 request (llm-req-0.json) ==='
cat /tmp/llm-req-0.json
echo ''
echo '=== end step 1 ==='

# Write raw response to a file to preserve newlines
echo $response > /tmp/raw-response.txt
echo '=== raw response ==='
cat /tmp/raw-response.txt
echo '=== end raw response ==='

# Extract tool_use_id from the TOOL: line in the response
# Format: STOP:tool_use\nTOOL:id:name:args
# The shell backtick breaks newlines into words, so TOOL:... is a separate word
toolline=''
for w in $response {
	if {~ $w 'TOOL:*'} {
		toolline=$w
	}
}
echo 'toolline:' $toolline

# Parse tool_use_id from TOOL:id:name:args
# We need the first field after TOOL:
# Strip the TOOL: prefix, then split on :
toolrest=`{echo $toolline | sed 's/^TOOL://'}
# toolrest is now id:name:args — get first :-separated field
toolid=`{echo $toolrest | sed 's/:.*//' }
echo 'parsed tool_use_id:' $toolid

# Now submit tool result with the CORRECT tool_use_id
echo 'TOOL_RESULTS
'^$toolid^'
Hello, Alice! Welcome!
---' > /n/llm/$id/ask
response2=`{cat /n/llm/$id/ask}
echo 'step 2 response:' $response2

# Check debug dump of step 2 request
echo '=== step 2 request (llm-req-1.json) ==='
cat /tmp/llm-req-1.json
echo ''
echo '=== end step 2 ==='

echo 'DONE'
