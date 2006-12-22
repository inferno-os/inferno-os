#!/dis/sh

grid/register -a resource Camera -a name Y2K -a model 'Kodak DC260' -a 'Image resource' 1 {demo/camera/camera.dis -v 2 -p 0 -n Y2K -f /dis/demo/camera/tkinterface.dis -f /dis/demo/camera/readjpg.dis -f /dis/demo/camera/camload.bit -f /dis/demo/camera/camproc.bit}
