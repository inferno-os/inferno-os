#!/dis/sh.dis
load std
luciuisrv
sleep 1
echo 'activity create Test' > /n/ui/ctl
cat /n/ui/activity/current
cat /n/ui/activity/0/label
echo 'role=human text=Hello world' > /n/ui/activity/0/conversation/ctl
cat /n/ui/activity/0/conversation/0
ls /n/ui/activity/0/
echo 'resource add path=/n/sensors/adsb label=ADS-B type=sensor status=streaming latency=2' > /n/ui/activity/0/context/ctl
cat /n/ui/activity/0/context/resources/0
echo 'create id=air-pic type=radar label=Air Picture' > /n/ui/activity/0/presentation/ctl
ls /n/ui/activity/0/presentation/
cat /n/ui/activity/0/presentation/air-pic/type
echo 'warning Peer requesting attention' > /n/ui/notification
cat /n/ui/notification
echo PASS
