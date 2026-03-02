#!/dis/sh.dis
#
# Git integration test: clone + add + commit + shell scripts
#

load std

echo '=========================================='
echo 'Git Integration Test'
echo '=========================================='

failed=0

echo ''
echo 'Step 1: Start network services'
ndb/cs

echo ''
echo 'Step 2: Clone octocat/Hello-World'
if {cmd/git/clone -v https://github.com/octocat/Hello-World /tmp/hw} {
	echo 'PASS: clone succeeded'
} {
	echo 'FAIL: clone failed'
	raise 'fail:clone'
}

echo ''
echo 'Step 3: Test git/log (shell script)'
if {sh /dis/cmd/git/log.sh /tmp/hw} {
	echo 'PASS: log succeeded'
} {
	echo 'FAIL: log failed'
	failed=1
}

echo ''
echo 'Step 4: Test git/status (shell script) — clean tree'
if {sh /dis/cmd/git/status.sh /tmp/hw} {
	echo 'PASS: status succeeded'
} {
	echo 'FAIL: status failed'
	failed=1
}

echo ''
echo 'Step 5: Modify a file'
echo 'modified by infernode git' >/tmp/hw/README

echo ''
echo 'Step 6: Test git/status — should show M README'
sh /dis/cmd/git/status.sh /tmp/hw
echo '(check output above for M README)'

echo ''
echo 'Step 7: Test git/diff — should show diff'
sh /dis/cmd/git/diff.sh /tmp/hw
echo '(check output above for diff)'

echo ''
echo 'Step 8: git/add'
if {cmd/git/add -v /tmp/hw/README} {
	echo 'PASS: add succeeded'
} {
	echo 'FAIL: add failed'
	failed=1
}

echo ''
echo 'Step 9: git/commit'
if {cmd/git/commit -v -m 'test commit from infernode' /tmp/hw} {
	echo 'PASS: commit succeeded'
} {
	echo 'FAIL: commit failed'
	failed=1
}

echo ''
echo 'Step 10: git/log after commit — should show new commit at top'
sh /dis/cmd/git/log.sh /tmp/hw

echo ''
echo '=========================================='
if {~ $failed 0} {
	echo 'All git integration tests PASSED'
} {
	echo 'Some tests FAILED'
	raise 'fail:git integration'
}
echo '=========================================='
