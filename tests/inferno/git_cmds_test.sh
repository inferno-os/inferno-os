#!/dis/sh.dis
#
# Git commands integration test (offline — no network required)
#
# Tests: init, add, commit, branch, checkout, merge, rm, log, status
#

load std

echo '=========================================='
echo 'Git Commands Integration Test (offline)'
echo '=========================================='

failed=0

echo ''
echo 'Step 1: git/init'
if {cmd/git/init /tmp/testrepo} {
	echo 'PASS: init succeeded'
} {
	echo 'FAIL: init failed'
	raise 'fail:init'
}

echo ''
echo 'Step 2: Create a file, git/add, git/commit'
echo 'hello world' >/tmp/testrepo/README.md
if {cmd/git/add /tmp/testrepo/README.md} {
	echo 'PASS: add succeeded'
} {
	echo 'FAIL: add failed'
	failed=1
}
if {cmd/git/commit -m 'initial commit' /tmp/testrepo} {
	echo 'PASS: commit succeeded'
} {
	echo 'FAIL: commit failed'
	failed=1
}

echo ''
echo 'Step 3: git/branch (list — should show * main)'
cmd/git/branch /tmp/testrepo

echo ''
echo 'Step 4: git/branch develop (create branch)'
if {cmd/git/branch /tmp/testrepo develop} {
	echo 'PASS: branch create succeeded'
} {
	echo 'FAIL: branch create failed'
	failed=1
}

echo ''
echo 'Step 5: git/branch (list — should show main and develop)'
cmd/git/branch /tmp/testrepo

echo ''
echo 'Step 6: git/checkout develop'
if {cmd/git/checkout /tmp/testrepo develop} {
	echo 'PASS: checkout succeeded'
} {
	echo 'FAIL: checkout failed'
	failed=1
}

echo ''
echo 'Step 7: Create 2nd file on develop, add, commit'
echo 'feature work' >/tmp/testrepo/feature.txt
if {cmd/git/add /tmp/testrepo/feature.txt} {
	echo 'PASS: add on develop succeeded'
} {
	echo 'FAIL: add on develop failed'
	failed=1
}
if {cmd/git/commit -m 'add feature' /tmp/testrepo} {
	echo 'PASS: commit on develop succeeded'
} {
	echo 'FAIL: commit on develop failed'
	failed=1
}

echo ''
echo 'Step 8: git/checkout main'
if {cmd/git/checkout /tmp/testrepo main} {
	echo 'PASS: checkout main succeeded'
} {
	echo 'FAIL: checkout main failed'
	failed=1
}

echo ''
echo 'Step 9: git/merge develop (fast-forward)'
if {cmd/git/merge /tmp/testrepo develop} {
	echo 'PASS: merge succeeded'
} {
	echo 'FAIL: merge failed'
	failed=1
}

echo ''
echo 'Step 10: git/rm -c feature.txt (unstage)'
echo 'staged' >/tmp/testrepo/staged.txt
cmd/git/add /tmp/testrepo/staged.txt
if {cmd/git/rm -c /tmp/testrepo/staged.txt} {
	echo 'PASS: rm -c succeeded'
} {
	echo 'FAIL: rm -c failed'
	failed=1
}

echo ''
echo 'Step 11: git/branch -d develop (delete branch)'
if {cmd/git/branch -d /tmp/testrepo develop} {
	echo 'PASS: branch delete succeeded'
} {
	echo 'FAIL: branch delete failed'
	failed=1
}

echo ''
echo '=========================================='
if {~ $failed 0} {
	echo 'All git commands tests PASSED'
} {
	echo 'Some tests FAILED'
	raise 'fail:git commands'
}
echo '=========================================='
