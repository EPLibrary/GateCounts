#!/bin/bash
#######################################################################
#
# Report data for all the gates at a given branch.
#
#    Copyright (C) 2017  Andrew Nisbet, Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
#######################################################################
#
# outputs data for all the gates at a given branch into 1 spreadsheet
# and mails the results to ILSadmins@epl.ca.
#
# Dependencies: pipe.pl patroncount mailx uuencode
#
########################################################################
BRANCH=''
VERSION="0.2.01"
ADDRESSES="ilsadmins@epl.ca"

###############
# Display usage message.
# param:  none
# return: none
usage()
{
	echo "Usage: $0 [-options]" >&2
	echo " Outputs all the gate count data for all the gates at a given branch," >&2
	echo " and emails the results." >&2
	echo " -b{branch} - 3 character branch code, case insensitive." >&2
	echo " -d'{start} {end}' - Defines a given date range. Date format 'yyyy-mm-dd hh:mm:ss'." >&2
	echo " -x - Show this message." >&2
	echo " " >&2 
	echo " Examples of valid input:" >&2
	echo "   $0 -bwmc -d'2018-03-01 09:20:00 2018-03-12 21:05:00'" >&2
	echo "   Version: $VERSION" >&2
	exit 1
}

while getopts ":b:d:x" opt; do
  case $opt in
	b)	echo "-b triggered with '$OPTARG'" >&2
		BRANCH=$(echo "$OPTARG" | pipe.pl -ec0:uc -oc0)
		echo "Branch: '$BRANCH'" >&2
		;;
	d)	echo "-d triggered with date time of '$OPTARG'" >&2
		START_TIMESTAMP=$(echo "$OPTARG" | pipe.pl -W'\s+' -oc0,c1 -h' ')
		END_TIMESTAMP=$(echo "$OPTARG" | pipe.pl -W'\s+' -oc2,c3 -h' ')
		echo "Timestamp range: '$START_TIMESTAMP' - '$END_TIMESTAMP'" >&2
		;;
	x)	usage
		;;
	\?)	echo "Invalid option: -$OPTARG" >&2
		usage
		;;
	:)	echo "Option -$OPTARG requires an argument." >&2
		usage
		;;
  esac
done
# If the branch is empty exit early
[[ -z "$BRANCH" ]] && echo "**error, location required."  >&2 && usage
[[ -z "$START_TIMESTAMP" ]] && echo "**error, start date-time required."  >&2 && usage
[[ -z "$END_TIMESTAMP" ]] && echo "**error, end date-time required."  >&2 && usage
# zero out file contents.
echo "" >gatedata.$BRANCH.csv
for gate_id in $(echo "select GateId from gate_info  where Branch='$BRANCH';" | mysql --defaults-file=/home/ilsdev/mysqlconfigs/patroncount -N); do
	# https://unix.stackexchange.com/questions/205180/how-to-pass-password-to-mysql-command-line
	echo "select GateId, DateTime, InCount, OutCount from patron_count where GateId=$gate_id and DateTime>='$START_TIMESTAMP' and DateTime<='$END_TIMESTAMP';" | mysql --defaults-file=/home/ilsdev/mysqlconfigs/patroncount -N | pipe.pl -W'\s+' -Tcsv:"Gate,Date,Time,In,Out,$START_TIMESTAMP - $END_TIMESTAMP" >>gatedata.$BRANCH.csv
	echo "" >>gatedata.$BRANCH.csv
	echo "select GateId, DateTime, InCount, OutCount from patron_count where GateId=$gate_id and DateTime>='$START_TIMESTAMP' and DateTime<='$END_TIMESTAMP';" | mysql --defaults-file=/home/ilsdev/mysqlconfigs/patroncount -N | pipe.pl -W'\s+' -?add:c3,c4 | pipe.pl -4c0 | pipe.pl -dc1 -Jc0 -P -L2- -oc2,c0 -Tcsv:"Gate,Total Traffic,Summary" >>gatedata.$BRANCH.csv
	echo "" >>gatedata.$BRANCH.csv
done
echo "emailing: $ADDRESSES" >&2
uuencode gatedata.$BRANCH.csv gatedata.$BRANCH.csv | mailx -a'From:ilsdev@ilsdev1.epl.ca' -s"$BRANCH gate data $START_TIMESTAMP - $END_TIMESTAMP" "$ADDRESSES"
# EOF
