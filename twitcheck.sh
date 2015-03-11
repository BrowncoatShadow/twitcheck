#!/bin/bash
# twitcheck - A twitch.tv Stream Checker by BrowncoatShadow and Crendgrim
# Useage: Copy settings.default.sh to settings.sh, configure settings and add this script to crontab.

# BOOTSTRAPING

# Include settings if they exist; create them from default template first otherwise
TC_BASEDIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
[[ -f "$HOME/.config/twitcheckrc" ]] || sed "s#<INSTALL_DIR>#$TC_BASEDIR#g" "$TC_BASEDIR/twitcheckrc.default" > "$HOME/.config/twitcheckrc"

# Load settings
source $HOME/.config/twitcheckrc

# Generate folders and files if they do not exist
if [[ ! -f $DATAFILE ]]
then
	mkdir -p $(dirname $DATAFILE)
	touch $DATAFILE
fi
if [[ ! -f $DBFILE ]]
then
	mkdir -p $(dirname $DBFILE)
	touch $DBFILE
fi

# Cleanup: If the database file is older than 2 hours, consider it outdated and remove its contents.
[[ $((`date +%s`-`stat -c %Y $DBFILE`)) -gt 7200 ]] && echo > $DBFILE
# 

# BOOTSTRAPING END

# Check if script has been called with command-line arguments.
if [[ -n $1 ]]
then
	# Use arguments instead of settings rc file.
	list=$*
	unset DBFILE
else
	# Check if we have a user set or any channels to follow.
	if [[ -z "$USER" && -z "$FOLLOWLIST" ]]
	then
		>&2 echo "You have to supply a user to fetch followed channels from, or set a FOLLOWLIST in the config!"
		>&2 echo "The configuration file can be found at $HOME/.config/twitcheckrc"
		exit
	else
		# Use the specified followlist, if set.
		list=$FOLLOWLIST

		# If user is set fetch users follow list and add them to the list.
		[[ -n $USER ]] && list="$list "$(curl -s --header 'Client-ID: '$CLIENT -H 'Accept: application/vnd.twitchtv.v3+json' -X GET "https://api.twitch.tv/kraken/users/$USER/follows/channels?limit=100" | jq -r '.follows[] | .channel.name' | tr '\n' ' ')
	fi
fi

# Sanitize the list for the fetch url.
urllist=$(echo $list | sed 's/ /\,/g')

# Fetch the JSON for all followed channels.
curl -s --header 'Client-ID: '$CLIENT -H 'Accept: application/vnd.twitchtv.v3+json' -X GET "https://api.twitch.tv/kraken/streams?channel=$urllist&limit=100" > $DATAFILE

# Main function
main() {

	# Check if stream is active.
	name=$(cat $DATAFILE | jq -r '.streams[] | select(.channel.name=="'$1'") | .channel.name')

	if [ "$name" == "$1" ]
	then
		# Check if it has been active since last check.
		[[ $DBFILE ]] && dbcheck=$(cat $DBFILE | grep "^$1")

		notify=true

		# Grab important info from JSON check.
		schannel=$(cat $DATAFILE | jq -r '.streams[] | select(.channel.name=="'$1'") | .channel.display_name')
		sgame=$(cat $DATAFILE | jq -r '.streams[] | select(.channel.name=="'$1'") | .channel.game')
		slink=$(cat $DATAFILE | jq -r '.streams[] | select(.channel.name=="'$1'") | .channel.url')
		sstatus=$(cat $DATAFILE | jq -r '.streams[] | select(.channel.name=="'$1'") | .channel.status')

		[[ "$sgame" == null || "$sstatus" == null ]] && return # sometimes the API sends us broken results. Ignore these.

		# Already streaming last time, check for updates
		if [ -n "$dbcheck" ]
		then

			notify=false

			IFS=`printf "\u2008"` read -ra dbdata <<< "$dbcheck"
			dbgame=${dbdata[1]}
			dbstatus=${dbdata[2]}
			
			# Notify when game or status change
			[[ "$dbgame" != "$sgame" || "$dbstatus" != "$sstatus" ]] && notify=true

		fi

		if [ $notify == true ]
		then

			if [ $DBFILE ]
			then
				# Add streamer to currently streaming DB; remove him first to discard old information (only status/game may have changed).
				DEL=`printf "\u2008"` # use Unicode 2008 ('PUNCTUATION SPACE') as a delimiter for the database file. This is a key that will not appear in the Twitch status.
				sed -i "/^$1$DEL/d" $DBFILE
				echo "$1$DEL$sgame$DEL$sstatus" >> $DBFILE
			fi

			# Send notification. NOTE This method has not yet been tested, and the variable probably needs to be renamed, but "notify" is already taken.
			$MODULE "$schannel" "$sgame" "$sstatus" "$slink"

		else

			# Exit if already streaming in past check and no updates.
			return 

		fi
	else
		# Remove from steaming DB if exists.
		[[ $DBFILE ]] && sed -i "/^$1$(printf "\u2008")/d" $DBFILE
	fi
}

# Run the main function for each stream.
for var in $list
do
	main $var
done
