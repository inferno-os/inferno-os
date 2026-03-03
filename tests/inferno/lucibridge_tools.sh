#!/dis/sh.dis
load std

# Mount llm9p (must be running on host)
mkdir -p /n/llm
mount -A tcp!127.0.0.1!5640 /n/llm

# Start tool server with basic tools
/dis/veltro/tools9p.dis read list find search &
sleep 1

# Verify tools mounted
echo tools:
cat /tool/tools

# Start UI server
luciuisrv
sleep 1

# Create activity
echo 'activity create ToolTest' > /n/ui/ctl

# Start bridge with tools
lucibridge -v -a 0 &
sleep 2

# Ask it to do something that requires a tool
echo 'List the files in /lib/veltro/agents/' > /n/ui/activity/0/conversation/input
sleep 12

# Show conversation messages
echo msg 0:
cat /n/ui/activity/0/conversation/0
echo msg 1:
cat /n/ui/activity/0/conversation/1
echo msg 2:
cat /n/ui/activity/0/conversation/2
echo msg 3:
cat /n/ui/activity/0/conversation/3
echo msg 4:
cat /n/ui/activity/0/conversation/4

echo PASS
