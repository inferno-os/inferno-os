#!/dis/sh.dis
# Lucifer startup script for Windows
# Usage: sh /dis/lucifer-start.sh
load std

# Set command search path
path=(/dis .)

# Get username and set up home
user="{cat /dev/user}

# Mount namespace generator
mount -ac {mntgen} /n >[2] /dev/null

# Initialize IP networking
bind -a '#I' /net >[2] /dev/null
ndb/cs

# Start native LLM server (self-mounts at /n/llm)
llmsrv &
sleep 1

# Set up home directory
home=/usr/^$user
if {! ftest -d $home} {
	mkdir -p $home
}
if {! ftest -d $home/tmp} {
	mkdir -p $home/tmp
}
mkdir -p /tmp >[2] /dev/null
bind -bc $home/tmp /tmp >[2] /dev/null

# Lucifer checks for /usr/inferno/tmp (hardcoded path)
mkdir -p /usr/inferno/tmp >[2] /dev/null

# Start UI server
luciuisrv

# Create default activity
echo activity create Main > /n/ui/ctl

# Register tools
/dis/veltro/tools9p -m /tool -p /dis/wm read list find search grep ask diff json memory websearch http write edit present todo gap editor

# Start bridge (background)
lucibridge -v &

# Launch Lucifer GUI (blocks)
lucifer
