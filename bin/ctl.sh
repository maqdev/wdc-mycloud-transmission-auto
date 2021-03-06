#!/bin/bash

set -e

DRIVE_STATE=`/sbin/hdparm -C /dev/sda | grep 'drive state is: ' | awk '{print $4}'`
if [ "$DRIVE_STATE" == "standby" ]; then
	exit
fi

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games

echo --------------------------------
date

WORK_DIR=/DataVolume/shares/Public/tt
INBOX_DIR=${WORK_DIR}/inbox
PROGRESS_DIR=${WORK_DIR}/progress
VPN_IP=$1
VPN_CFG=$2

echo VPN_IP = $VPN_IP

if [[ -z "$VPN_IP" ]]; then
	echo "Please specify IP address"
	exit
fi

if [[ -z "$VPN_CFG" ]]; then
	echo "Please specify VPN configuration"
	exit
fi

MY_IP=`wget -qO- http://wishsecret.ly/ip.php`

if [[ $MY_IP == $VPN_IP ]]; then
  	echo "VPN: ON ($MY_IP)"
else
	echo "VPN: OFF ($MY_IP)"
fi

function stopVPN {
	echo "Killing openvpn"
	ps ax | grep 'openvpn' | grep -vw grep | awk '{print $1}' | xargs kill -s kill
}

function startVPN {
	stopVPN
	sleep 5
	CMD="cd /etc/openvpn && openvpn --config '$VPN_CFG' &"
	echo "Executing: $CMD"
   	bash -c "$CMD"
   	sleep 10
}

function startTransmission {
	if [[ "$(ps -ef|grep -v grep|grep transmission-daemon)" == "" ]] ; then
		transmission-daemon
		sleep 10

		transmission-remote --list | while read line; do
			TR_ID=`echo "$line" | cut -c1-4 | tr -d ' '`
			re='^[0-9]+$'
			if [[ $TR_ID =~ $re ]] ; then
				transmission-remote -t "$TR_ID" --start
			fi
		done
	fi
}

function stopTransmission {
	transmission-stop
}

function updateProgressDir {
	#rm -rf ${PROGRESS_DIR}/*
	touch "${PROGRESS_DIR}/processing.txt"

	transmission-remote --list | while read line; do
		TR_ID=`echo "$line" | cut -c1-4 | tr -d ' '`
		re='^[0-9]+$'
		if [[ $TR_ID =~ $re ]] ; then
			TR_PROGRESS=`echo "$line" | cut -c5-8 | tr -d ' '`
			TR_SIZE=`echo "$line" | cut -c9-19 | tr -d ' '`
			TR_ETA=`echo "$line" | cut -c22-32 | tr -d ' '`
			TR_STATUS=`echo "$line" | cut -c54-67 | tr -d ' '`
			TR_NAME=`echo "$line" | cut -c68-999 | tr -d ' '`
			TR_INFO_FILE="${PROGRESS_DIR}/${TR_ID}-${TR_STATUS}-${TR_PROGRESS}-${TR_ETA}-${TR_SIZE}-${TR_NAME}.txt"
			echo "$line" > "$TR_INFO_FILE"
			transmission-remote -t "$TR_ID" -i >> "$TR_INFO_FILE"
		fi
  	done

  	find "${PROGRESS_DIR}/" -type f ! -newer "${PROGRESS_DIR}/processing.txt" -delete
  	rm -f "${PROGRESS_DIR}/processing.txt"
  	# fls "${PROGRESS_DIR}"
}

rm -rf $INBOX_DIR/.*.torrent
shopt -s nullglob
shopt -s dotglob # To include hidden files
HAS_WORK=0
inputFiles=($INBOX_DIR/*.torrent)
if [ ${#inputFiles[@]} -gt 0 ]; then
	HAS_WORK=1
	echo "Input files: $inputFiles";
	if [[ $MY_IP == $VPN_IP ]]; then
		startTransmission
		cd $INBOX_DIR/
		for file in *.torrent
		do
			echo "Starting download of: $file"
		  	transmission-remote --add ${INBOX_DIR}/"$file"
		  	rm -f ${INBOX_DIR}/"$file"
		  	updateProgressDir
		done
	else
                echo "Starting VPN"
                startVPN
	fi
fi

rm -rf $PROGRESS_DIR/._*
cd $PROGRESS_DIR/
for file in *
do
	# echo "Checking status of: $file" ...
	if [[ $file == *-Stopped-* ]]; then
	  	true # echo " STOPPED"
	else
		if [[ $file == *-100%-Done-* ]] || [[ $file == *-Idle-100%-Unknown-* ]] || [[ $file == *-Seeding-100%-* ]]; then
			true # echo " COMPLETE"
		else
			true # echo " IN-PROGRESS"
			HAS_WORK=1
		fi
	fi
done

echo "Has work: $HAS_WORK"

if [ $HAS_WORK -ne 0 ];then
	if [[ $MY_IP == $VPN_IP ]]; then
                startTransmission
                updateProgressDir
	else
 		stopTransmission
 		echo "Starting VPN"
 		startVPN
 	fi
else
	stopTransmission
	stopVPN
fi
