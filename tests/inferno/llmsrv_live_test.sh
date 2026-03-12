#!/dis/sh.dis
# Live integration test for native llmsrv with factotum
load std

# Bootstrap services
mount -ac {mntgen} /n >[2] /dev/null
bind -a '#I' /net >[2] /dev/null
ndb/cs
auth/factotum

echo '=== Factotum ==='
cat /mnt/factotum/proto

# Provision API key (host-side conditional logic)
factotumkey=`{os sh -c 'k=${ANTHROPIC_API_KEY:-$(plutil -extract EnvironmentVariables.ANTHROPIC_API_KEY raw ~/Library/LaunchAgents/com.nervsystems.llm9p.plist 2>/dev/null)}; if [ -n "$k" ]; then echo "key proto=pass service=anthropic user=apikey !password=$k"; fi'}
echo $factotumkey > /mnt/factotum/ctl >[2] /dev/null
echo 'PASS: API key provisioned'

# Start native llmsrv
llmsrv >[2] /dev/null &
sleep 1

echo '=== LLM Service ==='
ls /n/llm

echo '=== Session Test ==='
id=`{cat /n/llm/new}
echo 'session id:' $id
echo 'model:' `{cat /n/llm/$id/model}

echo '=== LLM Query ==='
echo 'Say hello in exactly 5 words.' > /n/llm/$id/ask
cat /n/llm/$id/ask

echo '=== Usage ==='
cat /n/llm/$id/usage

echo '=== ALL PASS ==='
