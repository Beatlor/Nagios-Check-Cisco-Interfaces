#!/bin/bash
#
#Copyright (C) 2021 Stephan Callsen
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
#associated documentation files (the "Software"), to deal in the Software without restriction,
#including without limitation the rights to use, copy, modify, merge, publish, distribute,
#sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#The above copyright notice and this permission notice shall be included in all copies or substantial
#portions of the Software.
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
#LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
#IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
#SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#
# Version        1.1
# Author         Stephan Callsen
# Date           Nov. 2021
#

# Nagios return Codes
# 0 => OK
# 1 => WARNING
# 2 => CRITICAL
# 3 => UNKNOWN

#Initialize variables
version="1.1"
RESULT_Ok=0
RESULT_Critical=2
RESULT_Warning=1
RESULT_EXIT_Ok=0
RESULT_EXIT_Warning=1
RESULT_EXIT_Critical=2
EXIT_STATE=0
ERROR_DIS=0
PERF="false"
let interfaceWithErrors=0
UNAME='JonDoe'
PASSWD='verysecret'

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

# Subroutines
function version() {
  echo "  Version: ${version} - License: MIT"
}

#usage info
function usage() {
  echo ""
  version
  echo '''
  Usage: check_cisco-error.sh -H hostname [-u username] [-p password] [-P] [-h]
  -P Performance output
  -h help (this output)
  Example check_cisco-error.sh -H 1.2.3.4 -u Jon_Doe -p VerySecret! -P
  '''
}

while getopts ":H:u:p:Ph" opt; do
  case ${opt} in
    H)
      HOSTADDRESS=$OPTARG
      ;;
    p)
      PASSWD=$OPTARG
      ;;
    u)
      UNAME=$OPTARG
      ;;
    P)
      PERF="true"
      ;;
    h)
      usage
      exit 3
      ;;
    \?)
      echo "Invalid option: $OPTARG" 1>&2
      exit 3
      ;;
    :)
      echo "Invalid option: $OPTARG requires an argument" 1>&2
      exit 3
      ;;
    *)
      usage
      exit 3
      ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$HOSTADDRESS" ]; then
  echo "Need at least the Hostaddress!"
  exit 3
fi

TMPFILE="/tmp/interfaces-$HOSTADDRESS"

nc --wait 2 $HOSTADDRESS 22 < /dev/null &> /dev/null
if [ $? != 0 ]; then
  echo "Connection failed"
  exit 3
fi

if [ -f "$TMPFILE" ]; then
  rm -f /tmp/interfaces-$HOSTADDRESS
fi

/usr/bin/expect <<EOF > /dev/null
set timeout 10
spawn ssh $UNAME@$HOSTADDRESS
expect "Password: "
send "$PASSWD\n"
expect "#$"
log_file /tmp/interfaces-$HOSTADDRESS
send "term length 0\r"
expect "#$"
send "sh interfaces | i Vlan|Port|Local|Ethernet|errors|CRC|collisions|drops|late|deferred\r"
expect "#$"
send "term length 40\r"
expect "#$"
log_file
send "exit\r"
EOF

interfaceList=$(cat /tmp/interfaces-$HOSTADDRESS | head -n-2 | tail -n+3 | sed -e 's/^[ \t]*//' |tr -d "\r" | tr "\n" "," | sed -E 's/(TengigabitEthernet|GigabitEthernet|FastEthernet[^,]|Vlan+)/\n\1/g' | tail -n+2 |awk 'FS= " " { print $1 }')

PhyInterfacesCountUp=$(cat /tmp/interfaces-$HOSTADDRESS | head -n-2 | tail -n+3 | sed -e 's/^[ \t]*//' |tr -d "\r" | tr "\n" "," | sed -E 's/(TengigabitEthernet|GigabitEthernet|FastEthernet[^,]+)/\n\1/g' | awk 'FS= "," { print $1 }' | grep up | wc -l)
PhyInterfacesCountDown=$(cat /tmp/interfaces-$HOSTADDRESS | head -n-2 | tail -n+3 | sed -e 's/^[ \t]*//' |tr -d "\r" | tr "\n" "," | sed -E 's/(TengigabitEthernet|GigabitEthernet|FastEthernet[^,]+)/\n\1/g' | awk 'FS= "," { print $1 }' | grep down | wc -l)

let interfaceCount=$(echo "$interfaceList" | wc -l)

for Interface in $(echo $interfaceList); do
  line=""
  line=$(cat /tmp/interfaces-$HOSTADDRESS | head -n-2 | tail -n+3 | sed -e 's/^[ \t]*//' |tr -d "\r" | tr "\n" "," | sed -E 's/(TengigabitEthernet|GigabitEthernet|FastEthernet[^,]|Vlan+)/\n\1/g' | tail -n+2 | grep "$Interface ")
  UpDown=$(echo $line | awk 'BEGIN { FS = "," };{print $1}' | awk '{print $3}')
  if [ $UpDown = "up" ] && [[ ! $Interface =~ Vlan ]]; then
    let total_errors=0
    Connect=$(echo $line | awk 'BEGIN { FS = "," };{print $2}' | awk '{print $5}'|tr -d "()")
    if [ $Connect = "err-disabled" ]; then
      let ERROR_DIS=1
    fi
    #echo $line
    let error_in=$(echo $line | awk 'BEGIN { FS = "," };{print $6}' | awk '{print $1}')
    let error_out=$(echo $line | awk 'BEGIN { FS = "," };{print $11}' | awk '{print $1}')
    let error_crc=$(echo $line | awk 'BEGIN { FS = "," };{print $7}' | awk '{print $1}')
    let error_collisions=$(echo $line | awk 'BEGIN { FS = "," };{print $12}' | awk '{print $1}')
    let error_unkowndrops=$(echo $line | awk 'BEGIN { FS = "," };{print $14}' | awk '{print $1}')
    let error_latec=$(echo $line | awk 'BEGIN { FS = "," };{print $16}' | awk '{print $1}')
    let awk_nr=$(echo $line | awk 'BEGIN { FS = "," }; {for (i=1;i<=NF;i++) if($i ~/deferred/) print i}')
    if (( $awk_nr > 0 )); then
      let error_deferred=$(echo $line | awk 'BEGIN { FS = "," };{print $'"$awk_nr"'}' | awk '{print $1}')
    else
      let error_deferred="0"
    fi
    let total_errors=error_in+error_out+error_crc+error_collisions+error_unkowndrops+error_latec
    let global_errors+=total_errors

    if (( $total_errors > 0 )); then
      printf -v Dump "WARNING Interface %-23s in Operationsstate %4s LineState %10s\n-       ErrorsIn: %i ErrorsOut: %i CRC: %i Collisions: %i UnkD: %i LateCollisions: %i Deferred: %i\n" $Interface $UpDown $Connect $error_in $error_out $error_crc $error_collisions $error_unkowndrops $error_latec $error_deferred
      out_line+=$Dump
      let interfaceWithErrors+=1
      EXIT_STATE=1 # Warning
    else
      printf -v Dump "OK      Interface %-23s in Operationsstate %4s LineState %10s - No Errors.\n" $Interface $UpDown $Connect
      out_line+=$Dump
    fi
  fi
done

if (( $ERROR_DIS == 1 )); then EXIT_STATE=2; fi

if [ -f $TMPFILE ]; then
  rm -f /tmp/interfaces-$HOSTADDRESS
fi

printf -v interfaceSummary "Output UP: %s Down: %s Interfaces with Errors: %i Interfaces on Chassis: %i" $PhyInterfacesCountUp $PhyInterfacesCountDown $interfaceWithErrors $interfaceCount

if [ $EXIT_STATE -gt $RESULT_Warning ]; then
  printf "Critical Errors found on Interfaces. %s" $interfaceSummary
  echo -e "$out_line"
  if [ $PERF = "true" ]; then
    printf "|Up=%s;; Down=%s;; IntWithErrors=%i;; Errors=%i;;\n" $PhyInterfacesCountUp $PhyInterfacesCountDown $interfaceWithErrors $global_errors
  else
    printf "\n"
  fi
  exit $RESULT_EXIT_Critical
fi

if [ $EXIT_STATE -eq $RESULT_Ok ]; then
  echo "OK no errors found on Interfaces. $interfaceSummary"
  echo -e "$out_line"
  if [ $PERF = "true" ]; then
    printf "|Up=%s;; Down=%s;; IntWithErrors=%i;; Errors=%i;;\n" $PhyInterfacesCountUp $PhyInterfacesCountDown $interfaceWithErrors $global_errors
  else
    printf "\n"
  fi
  exit $RESULT_EXIT_Ok
fi

if [ $EXIT_STATE -eq $RESULT_Warning ]; then
  echo "WARNING Errors found on Interfaces. $interfaceSummary"
  echo -e "$out_line"
  if [ $PERF = "true" ]; then
    printf "|Up=%s;; Down=%s;; IntWithErrors=%i;; Errors=%i;;\n" $PhyInterfacesCountUp $PhyInterfacesCountDown $interfaceWithErrors $global_errors
  else
    printf "\n"
  fi
  exit $RESULT_EXIT_Warning
fi

exit 0
