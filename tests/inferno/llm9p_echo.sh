#!/dis/sh.dis
load std
mkdir -p /n/llm
mount -A tcp!127.0.0.1!5640 /n/llm
echo ls:
ls /n/llm
echo new session:
cat /n/llm/new
echo ls after clone:
ls /n/llm
echo model:
cat /n/llm/0/model
echo ask:
echo 'Hello from Lucifer' > /n/llm/0/ask
cat /n/llm/0/ask
echo PASS
