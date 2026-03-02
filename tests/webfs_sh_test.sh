#!/dis/sh.dis
# webfs filesystem test via Inferno shell

load std

webfs /mnt/web &
sleep 1

echo '=== Test: clone ==='
id := `{cat /mnt/web/clone}
echo 'conn:' $id

echo '=== Test: write url to ctl ==='
echo 'url http://104.18.26.120' > /mnt/web/$id/ctl

echo '=== Test: write host header ==='
echo 'header Host: example.com' > /mnt/web/$id/ctl

echo '=== Test: read status ==='
cat /mnt/web/$id/status

echo '=== Test: read body (first 200 bytes) ==='
read 200 < /mnt/web/$id/body

echo '=== Test: read parsed/host ==='
cat /mnt/web/$id/parsed/host

echo '=== Test: read parsed/scheme ==='
cat /mnt/web/$id/parsed/scheme

echo '=== Test: second clone ==='
id2 := `{cat /mnt/web/clone}
echo 'conn2:' $id2

echo '=== ALL DONE ==='
