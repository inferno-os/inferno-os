#!/dis/sh
load std
autoload=std
ndb/cs

chatroom=$1

fn ck {
	or {$*} {
		echo chatclient: exiting >[1=2]
		raise error
	}
}
user="{cat /dev/user}

ck mount -A 'tcp!$registry!registry' /mnt/registry
ck /dis/grid/remotelogon wm/wm {
	k = /usr/$user/keyring/default
	grid/find -a resource chat -a pk `{getpk -s $k} Enter {demo/chat/chat /n/client} Shell {wm/sh}
}
