#!/bin/bash
#
# Run this script after core_install.sh
#
# Uncomment this statement for debug echos
DEBUG=1

scriptname="`basename $0`"
UDR_INSTALL_LOGFILE="/var/log/udr_install.log"

function dbgecho { if [ ! -z "$DEBUG" ] ; then echo "$*"; fi }

# ===== function get_user

function get_user() {
   # Check if there is only a single user on this system
   if (( `ls /home | wc -l` == 1 )) ; then
      USER=$(ls /home)
   else
      echo "Enter user name ($(echo $USERLIST | tr '\n' ' ')), followed by [enter]:"
      read -e USER
   fi
}

# ==== function check_user
# verify user name is legit

function check_user() {
   userok=false
   dbgecho "$scriptname: Verify user name: $USER"
   for username in $USERLIST ; do
      if [ "$USER" = "$username" ] ; then
         userok=true;
      fi
   done

   if [ "$userok" = "false" ] ; then
      echo "User name ($USER) does not exist,  must be one of: $USERLIST"
      exit 1
   fi

   dbgecho "using USER: $USER"
}

# ===== function CopyBinFiles

function CopyBinFiles() {

# Check if directory exists.
if [ ! -d "$userbindir" ] ; then
   mkdir $userbindir
fi

cp /home/$USER/n7nix/systemd/bin/* $userbindir
cp /home/$USER/n7nix/bin/* $userbindir
chown -R $USER:$USER $userbindir

echo
echo "FINISHED copying bin files"
}


# ===== main

echo "Initial core config script"

# Be sure we're running as root
if [[ $EUID != 0 ]] ; then
   echo "Must be root"
   exit 1
fi

START_DIR=$(pwd)

echo " === Verify not using default password"
# is there even a user pi?
ls /home | grep pi > /dev/null 2>&1
if [ $? -eq 0 ] ; then
   echo "User pi found"
   echo "Determine if default password is being used"

   # get salt
   SALT=$(grep -i pi /etc/shadow | awk -F\$ '{print $3}')

   PASSGEN=$(mkpasswd --method=sha-512 --salt=$SALT raspberry)
   PASSFILE=$(grep -i pi /etc/shadow | cut -d ':' -f2)

#   dbgecho "SALT: $SALT"
#   dbgecho "pass file: $PASSFILE"
#   dbgecho "pass  gen: $PASSGEN"

   if [ "$PASSFILE" = "$PASSGEN" ] ; then
      echo "User pi is using default password"
      echo "Need to change your password for user pi NOW"
      read -t 1 -n 10000 discard
      passwd pi
      if [ $? -ne 0 ] ; then
         echo "Failed to set password, exiting"
	 exit 1
      fi
   else
      echo "User pi not using default password."
   fi

else
   echo "User pi NOT found"
fi

# Check hostname
echo " === Verify hostname"
HOSTNAME=$(cat /etc/hostname | tail -1)
dbgecho "$scriptname: Current hostname: $HOSTNAME"

# Check for any of the default hostnames
if [ "$HOSTNAME" = "raspberrypi" ] || [ "$HOSTNAME" = "compass" ] || [ "$HOSTNAME" = "draws" ] ; then
   # Change hostname
   echo "Using default host name: $HOSTNAME, change it"
   echo "Enter new host name followed by [enter]:"
   read -t 1 -n 10000 discard
   read -e HOSTNAME
   echo "$HOSTNAME" > /etc/hostname
fi

# Get hostname again incase it was changed
HOSTNAME=$(cat /etc/hostname | tail -1)

echo "=== Set mail hostname"
echo "$HOSTNAME.localhost" > /etc/mailname

# Be sure system host name can be resolved

grep "127.0.1.1" /etc/hosts
if [ $? -eq 0 ] ; then
   # Found 127.0.1.1 entry
   # Be sure hostnames match
   HOSTNAME_CHECK=$(grep "127.0.1.1" /etc/hosts | awk {'print $2'})
   if [ "$HOSTNAME" != "$HOSTNAME_CHECK" ] ; then
      echo "Make host names match between /etc/hostname & /etc/hosts"
      sed -i -e "/127.0.1.1/ s/127.0.1.1\t.*/127.0.1.1\t$HOSTNAME ${HOSTNAME}.localnet/" /etc/hosts
   else
      echo "host names match between /etc/hostname & /etc/hosts"
   fi
else
   # Add a 127.0.1.1 entry to /etc/hosts
   sed -i '1i\'"127.0.1.1\t$HOSTNAME $HOSTNAME.localnet" /etc/hosts
   if [ $? -ne 0 ] ; then
      echo "Failed to modify /etc/hosts file"
   fi
fi

echo "=== Set time zone & current time"

DATETZ=$(date +%Z)
dbgecho "Time zone: $DATETZ"

if [ "$DATETZ" == "UTC" ] || [ "$DATETZ" == "GMT" ] ; then
   echo " === Set time zone"
   echo " ie. select America, then scroll down to 'Los Angeles'"
   echo " then hit tab & return ... wait for it"
   # pause to read above msg
   sleep 4
   dpkg-reconfigure tzdata
fi

echo "=== Set alsa levels for UDRC"

# Get list of users with home directories
USERLIST="$(ls /home)"
USERLIST="$(echo $USERLIST | tr '\n' ' ')"

get_user
check_user

userbindir=/home/$USER/bin
CopyBinFiles
cd $userbindir

# Adjust clock
# source ./set-time.sh

# Set alsa levels with script
#./set-udrc-din6.sh  > /dev/null 2>&1
# Sets left channel levels for Kenwood & right channel for Alinco
./set-udrc-both.sh  > /dev/null 2>&1
retcode="$?"
dbgecho "Set sound card levels return: $retcode"

cd $START_DIR

echo "$(date "+%Y %m %d %T %Z"): $scriptname: core config script FINISHED" >> $UDR_INSTALL_LOGFILE
echo
echo "core config script FINISHED"
echo
