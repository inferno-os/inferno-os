load alphabet std

typeset /fs

declare /fs/walk
declare /fs/entries
declare /fs/match
declare /fs/print

autoconvert /string /fs/fs /fs/walk
autoconvert /fs/fs /fs/entries /fs/entries
autoconvert /string /fs/gate /fs/match
autoconvert /fs/entries /fd /fs/print
