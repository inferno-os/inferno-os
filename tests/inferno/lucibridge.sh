#!/dis/sh.dis
load std

# Mount llm9p (must be running on host)
mkdir -p /n/llm
mount -A tcp!127.0.0.1!5640 /n/llm

# Start UI server
luciuisrv
sleep 1

# Create activity for the bridge
echo 'activity create BridgeTest' > /n/ui/ctl
echo activity created:
cat /n/ui/activity/0/label

# Start bridge in background (no /tool mount = chat-only mode)
lucibridge -v -a 0 &
sleep 2

# Send human input
echo 'What is the meaning of life?' > /n/ui/activity/0/conversation/input
sleep 8

# Check conversation messages
echo msg 0:
cat /n/ui/activity/0/conversation/0
echo msg 1:
cat /n/ui/activity/0/conversation/1

# Send a second message to test multi-turn
echo 'Summarize in one sentence.' > /n/ui/activity/0/conversation/input
sleep 8

echo msg 2:
cat /n/ui/activity/0/conversation/2
echo msg 3:
cat /n/ui/activity/0/conversation/3

echo PASS
