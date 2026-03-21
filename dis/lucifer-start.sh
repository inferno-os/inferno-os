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

# LLM service: read config from /lib/ndb/llm
llmmode=`{sed -n 's/^mode=//p' /lib/ndb/llm >[2] /dev/null}
if {~ $llmmode remote} {
	llmdial=`{sed -n 's/^dial=//p' /lib/ndb/llm}
	mount -A $llmdial /n/llm >[2] /dev/null
}{
	llmsrv &
	sleep 1
}

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

# Register tools with budget for task delegation
/dis/veltro/tools9p -m /tool -b read,list,find,search,grep,write,edit,diff,json,http,memory,todo,plan,spawn,websearch,keyring,launch,present,gap -p /dis/wm read list find present task memory gap keyring editor launch

# Start bridge with MA support (background)
lucibridge -a 0 -v -s &
sleep 1

# Create task dashboard
echo 'create id=tasks type=taskboard label=Tasks' > /n/ui/activity/0/presentation/ctl

# Launch Lucifer GUI (blocks)
lucifer
