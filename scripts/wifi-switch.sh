#!/bin/bash
#version 0.95-4-N/HS

# --mode {auto, ap, sta} --force-reload

#You may share this script on the condition a reference to RaspberryConnect.com 
#must be included in copies or derivatives of this script. 

#A script to switch between a wifi network and a non internet routed Hotspot
#Works at startup or with a seperate timer or manually without a reboot
#Other setup required find out more at
#http://www.raspberryconnect.com


# Parse scripts parameters
PARAMS=""

while (( "$#" )); do
  case "$1" in
    -m|--mode)
      mode=$2
      shift 2
      ;;
    -f|--force-reload)
      force=1
      shift
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      exit 1
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done
# set positional arguments in their proper place
eval set -- "$PARAMS"


wifidev="wlan0" #device name to use. Default is wlan0.
#use the command: iw dev ,to see wifi interface name 

IFSdef=$IFS
cnt=0
#These four lines capture the wifi networks the RPi is setup to use
wpassid=$(awk '/ssid="/{ print $0 }' /etc/wpa_supplicant/wpa_supplicant.conf | awk -F'ssid=' '{ print $2 }' ORS=',' | sed 's/\"/''/g' | sed 's/,$//')
IFS=","
ssids=($wpassid)
IFS=$IFSdef #reset back to defaults


#Note:If you only want to check for certain SSIDs
#Remove the # in in front of ssids=('mySSID1'.... below and put a # infront of all four lines above
# separated by a space, eg ('mySSID1' 'mySSID2')
#ssids=('mySSID1' 'mySSID2' 'mySSID3')

#Enter the Routers Mac Addresses for hidden SSIDs, seperated by spaces ie 
#( '11:22:33:44:55:66' 'aa:bb:cc:dd:ee:ff' ) 
mac=()

ssidsmac=("${ssids[@]}" "${mac[@]}") #combines ssid and MAC for checking

#Activate access point mode
ActivateAccessPointMode()
{
    ip link set dev "$wifidev" down
    ip a add 10.0.0.5/24 brd + dev "$wifidev"
    ip link set dev "$wifidev" up
    dhcpcd -k "$wifidev" >/dev/null 2>&1
    sleep 2
    systemctl start dnsmasq
    sleep 2
    systemctl start hostapd
}

#Deactivate access point mode
DeactivateAccessPointMode()
{
    ip link set dev "$wifidev" down
    systemctl stop hostapd
    sleep 2
    systemctl stop dnsmasq
    sleep 2   
}

#Activate station mode
ActivateStationMode()
{
    connected=false #result

    ip addr flush dev "$wifidev"
    ip link set dev "$wifidev" up
    dhcpcd  -n "$wifidev" >/dev/null 2>&1
    sleep 2
    wpa_supplicant -B -i "$wifidev" -c /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null 2>&1 

    sleep 20 #give time for connection to be completed to router

    if wpa_cli -i "$wifidev" status | grep 'ip_address' >/dev/null 2>&1 #check wifi connected
    then
        connected=true
    fi
}

#Deactivate station mode
DeactivateStationMode()
{
    wpa_cli terminate >/dev/null 2>&1
    sleep 2
    ip addr flush "$wifidev"
    ip link set dev "$wifidev" down
    rm -r /var/run/wpa_supplicant >/dev/null 2>&1

    connected=false
}

FindSSID()
{
    #Check to see what SSID's and MAC addresses are in range
    ssidChk=('NoSSid')
    i=0; j=0
    until [ $i -eq 1 ] #wait for wifi if busy, usb wifi is slower.
    do
        ssidreply=$((iw dev "$wifidev" scan ap-force | egrep "SSID:" | sed 's/.*SSID: //') 2>&1) >/dev/null 2>&1
	    
        arr=$(echo $ssidreply | tr " " "\n")

        echo -e "\nSSid's in range: "
        echo "===================================="
    	for x in $arr
    	do
    	    echo "$x"
    	done
	    echo -e "====================================\n"
        echo "Device Available Check try " $j

        if (($j >= 10)); 
        then #if busy 10 times goto hotspot
            echo "Device busy or unavailable 10 times, going to Hotspot"
            ssidreply=""
            i=1
	    elif echo "$ssidreply" | grep "No such device (-19)" >/dev/null 2>&1; then
            echo "No Device Reported, try " $j
	        #if no wifi device,ie usb wifi removed, activate wifi so when it is
	        #reconnected wifi to a router will be available
	        echo "No wifi device connected"
	        wpa_supplicant -B -i "$wifidev" -c /etc/wpa_supplicant/wpa_supplicant.conf >/dev/null 2>&1
	        exit 1
        elif echo "$ssidreply" | grep "Network is down (-100)" >/dev/null 2>&1 ; then
            echo "Network Not available, trying again" $j
            j=$((j + 1))
            sleep 2
	    elif echo "$ssidreplay" | grep "Read-only file system (-30)" >/dev/null 2>&1 ; then
		    echo "Temporary Read only file system, trying again"
		    j=$((j + 1))
		    sleep 2
	    elif ! echo "$ssidreply" | grep "resource busy (-16)"  >/dev/null 2>&1 ; then
            echo "Device Available, checking SSid Results"
		    i=1
	    else #see if device not busy in 2 seconds
            echo "Device unavailable checking again, try " $j
		    j=$((j + 1))
		    sleep 2
	    fi
    done

    for ssid in "${ssidsmac[@]}"
    do
        cleanssid=$(echo $ssid | tr -d '\r')
	    for x in $arr
    	do
		    if [ "$cleanssid" == "$x" ]
		    then
			    ssidmatch="true"
		    fi
	    done

        if [ "$ssidmatch" == "true" ]
        then
            #Valid SSid found, passing to script
            echo "Valid SSID Detected, assesing Wifi status"
            ssidChk=$ssid
            return 0
        else
            #No Network found, NoSSid issued"
            echo "No SSid found, assessing WiFi status"
            ssidChk='NoSSid'
        fi
    done
}

#no mode selected, get current mode
if [ -z ${mode+x} ]; # variable mode not exists
then
  if systemctl status hostapd | grep "(running)" >/dev/null 2>&1
  then #active access point mode
    mode="ap"
  else #active station mode
    mode="sta"
  fi
fi

if [ "$mode" == "ap" ];
then #Requested access point mode
    if systemctl status hostapd | grep "(running)" >/dev/null 2>&1;
    then #access point mode already running
        if [ ! -z ${force+x} ]; 
        then #configuration changed, force reload
            echo "Access point configuration changed, reloading..."
            DeactivateAccessPointMode
            sleep 2
            ActivateAccessPointMode
            echo "Access point active !"
        else
            echo "Access point already active"
        fi
    else #station mode running
        echo "Activating access point..."
        DeactivateStationMode
        sleep 2
        ActivateAccessPointMode
        echo "Access point active !"
    fi

elif [ "$mode" == "sta" ];
then #Requested station mode
    if wpa_cli -i "$wifidev" status | grep 'ip_address' >/dev/null 2>&1;
    then #station mode already running
        if [ ! -z ${force+x} ];
        then #configuration changed, force reload
            echo "Station configuration changed, reloading..."
            DeactivateStationMode
            sleep 2
            ActivateStationMode
            if [ "$connected" = true ] ;
            then
                echo "WiFi connected !"
            else #Failed to connect to wifi (check your wifi settings, password etc)
	            echo 'WiFi failed to connect !'            
            fi
        else
            echo "Wifi already connected"
        fi
    else
        echo "Activating station mode..."
        DeactivateAccessPointMode
        sleep 2
        ActivateStationMode
        if [ "$connected" = true ] ;
        then
            echo "WiFi connected !"
        else #Failed to connect to wifi (check your wifi settings, password etc)
	        echo 'WiFi failed to connect !'            
        fi
    fi 

elif [ "$mode" == "auto" ]; #Requested auto switch mode
then
    FindSSID

    #Create Hotspot or connect to valid wifi networks
    if [ "$ssidChk" != "NoSSid" ] 
    then #configured ssid in range, connect it
        if systemctl status hostapd | grep "(running)" >/dev/null 2>&1
        then #hotspot running
            echo "Activating station mode..."
            DeactivateAccessPointMode
            sleep 2
            ActivateStationMode
	        if [ "$connected" = true ] ;
            then
                echo "WiFi connected !"
            else #Failed to connect to wifi (check your wifi settings, password etc)
	            echo 'WiFi failed to connect, falling back to Hotspot...'
                DeactivateStationMode
                sleep 2
	            ActivateApMode
                echo "Access point active !"
	        fi
        elif { wpa_cli -i "$wifidev" status | grep 'ip_address'; } >/dev/null 2>&1
        then #Already connected
            if [ ! -z ${force+x} ]
            then #settings changed, force reconnect
                echo "Station configuration changed, reloading..."
                DeactivateStationMode
                sleep 2
                ActivateStationMode
	            if [ "$connected" = true ] ;
                then
                    echo "WiFi connected !"
                else #Failed to connect to wifi (check your wifi settings, password etc)
	                echo 'WiFi failed to connect, falling back to access point...'
                    DeactivateStationMode
                    sleep 2
	                ActivateApMode
                    echo "Access point active !"
                fi
            else
                echo "WiFi already connected"
            fi
        else #ssid exists and no hotspot running connect to wifi network
            echo "Activating station mode..."
            ActivateStationMode
	        if [ "$connected" = true ] ;
            then
                echo "WiFi connected !"
            else #Failed to connect to wifi (check your wifi settings, password etc)
	            echo 'WiFi failed to connect, falling back to access point...'
                DeactivateStationMode
                sleep 2
	            ActivateApMode
                echo "Access point active !"
            fi
        fi
    else #ssid or MAC address not in range
        if systemctl status hostapd | grep "(running)" >/dev/null 2>&1
        then #hotspot running
            if [ ! -z ${force+x} ]
            then #settings changed, force reconnect
                echo "Access point configuration changed, reloading..."
                DeactivateAccessPointMode
                sleep 2
                ActivateApMode
                echo "Access point active !"
            else
                echo "Access point already active"
            fi
        elif { wpa_cli status | grep "$wifidev"; } >/dev/null 2>&1
        then #station mode active
            echo "Activating access point mode..."
            DeactivateStationMode
            sleep 2
            ActivateApMode
            echo "Access point active !"
        else #"No SSID, activating Hotspot"
            echo "Activating access point mode..."
            ActivateApMode
            echo "Access point active !"
        fi
    fi
fi