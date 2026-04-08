# InferNode GUI boot sequence
# Runs AFTER profile (invoked as: sh -l /lib/lucifer/boot.sh)

# Login screen (unlocks secstore, loads keys into factotum)
wm/logon

# (Re-)start LLM service — profile's llmsrv may have failed pre-logon
# because the API key wasn't in factotum yet (secstore not yet unlocked).
if {! ftest -d /n/llm} {
	llmmode=`{sed -n 's/^mode=//p' /lib/ndb/llm >[2] /dev/null}
	if {~ $llmmode remote} {
		llmdial=`{sed -n 's/^dial=//p' /lib/ndb/llm}
		mount -A $llmdial /n/llm >[2] /dev/null
	}{
		llmsrv >[2] /dev/null &
	}
	sleep 1
}

# Wallet service
/dis/veltro/wallet9p.dis >[2] /dev/null &
sleep 1

# GUI services
luciuisrv
echo activity create Main > /n/ui/ctl
sleep 1
/dis/veltro/tools9p -v -m /tool -b read,list,find,search,grep,write,edit,exec,launch,spawn,diff,json,webfetch,git,memory,todo,plan,websearch,mail,keyring,present,gap -p /dis/wm read list find present say hear task memory gap keyring editor shell
lucibridge -a 0 -v -s >[2] /tmp/lucibridge.log &
sleep 1
echo 'create id=tasks type=taskboard label=Tasks' > /n/ui/activity/0/presentation/ctl
lucifer
