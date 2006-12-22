load std alphabet

type /string /fd /status /cmd /wfd

typeset /fs
type /fs/fs /fs/entries /fs/gate /fs/selector

typeset /grid
type /grid/endpoint

autoconvert fd status {(fd); /print $1 1}
autoconvert string fd /read
autoconvert cmd string /unparse
autoconvert wfd fd /w2fd

autoconvert fs entries /fs/entries
autoconvert string gate /fs/match
autoconvert entries fd /fs/print
autoconvert endpoint fd {(endpoint); /grid/local -v $1}

fn pretty {
	-{
		/echo {/pretty $1}
	} ${rewrite $1 /status}
}
