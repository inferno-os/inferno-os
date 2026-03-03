#!/dis/sh.dis
load std

# Mount llm9p
mkdir -p /n/llm
mount -A tcp!127.0.0.1!5640 /n/llm

# Start UI server
luciuisrv
sleep 1

# Create activity
echo 'activity create Chat' > /n/ui/ctl
echo activity:
cat /n/ui/activity/current

# Create LLM session
cat /n/llm/new

# Simulate human message
echo 'role=human text=What is the capital of France?' > /n/ui/activity/0/conversation/ctl
echo human msg:
cat /n/ui/activity/0/conversation/0

# Send to LLM and write response back
echo 'What is the capital of France?' > /n/llm/0/ask
resp := `{cat /n/llm/0/ask}
echo 'role=veltro text='^$resp > /n/ui/activity/0/conversation/ctl
echo veltro msg:
cat /n/ui/activity/0/conversation/1

echo PASS
