# InferNode GUI boot sequence
# Runs AFTER profile (invoked as: sh -l /lib/lucifer/boot.sh)

# Warm trfs cache for the secstore overlay so logon and secstored can
# find PAK/factotum files on second launch (trfs may not have read-ahead
# the directory contents yet when the overlay bind was set up in profile).
user=`{cat /dev/user}
ls /usr/inferno/secstore >[2] /dev/null
ls /usr/inferno/secstore/$user >[2] /dev/null

# Login screen (unlocks secstore, loads keys into factotum)
wm/logon

# (Re-)start LLM service — profile's llmsrv may have failed pre-logon
# because the API key wasn't in factotum yet (secstore not yet unlocked).
# Note: ftest -d /n/llm is useless here — mntgen auto-creates the stub.
# Check if the service is actually responding by opening /n/llm/new.
if {! ftest -f /n/llm/new} {
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
/dis/veltro/tools9p -v -m /tool -b read,list,find,search,grep,write,edit,exec,launch,spawn,diff,json,webfetch,git,say,editor,fractal,memory,todo,plan,websearch,mail,keyring,present,gap -p /dis/wm read list find present say hear task memory gap keyring editor shell
lucibridge -a 0 -v -s >[2] /tmp/lucibridge.log &
sleep 1
echo 'create id=tasks type=taskboard label=Tasks' > /n/ui/activity/0/presentation/ctl
lucifer
