#!/usr/bin/perl -w
###############################################################################
#
# Perl source file for project gatecountaudit
#
# Finds and repairs bad gate counts in patron count database.
#    Copyright (C) 2019  Andrew Nisbet
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
# Author:  Andrew Nisbet, Edmonton Public Library
# Created: Sat Sep  3 08:28:52 MDT 2016
# Rev:
#          0.8.0 - Add -U to set a specific count for all branches on a specific day.
#          0.7.6 - Add ordering by DateTime for queries where that makes sense.
#                  This is due to additional date entries that were added out of sequence.
#          0.7.4 - Fix -u to add comment strings without requiring
#                  special quoting.
#          0.7.3 - Fix date to today.
#          0.7.2 - Fix date to today.
#          0.7.1 - Fix double-pipe error in -R.
#          0.7.0 - Use absolute path to password file.
#          0.6.1 - Use absolute path to password file.
#          0.6.0 - Compute standard deviation of gate counts from a branch 
#                  over a date range.
#          0.5.0 - Reset gate ('-f') added to force counts for a branch
#                  to be recalculated.
#          0.4.0 - Report counts for a specific branch within a date
#                  range ('-h').
#          0.3.01 - Fix usage.
#          0.3 -   Fix loop bug.
#          0.2 -   Repair (-R) tested add audit - find missing entries.
#          0.1 -   Repair (-r) tested.
#
###############################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;
$ENV{'PATH'}  = '/bin:/usr/bin:/usr/local/bin:/home/ils/gatecounts:/home/ils/gatecounts/bin:/home/ils/bin';
$ENV{'SHELL'} = '/bin/bash';
my $VERSION            = qq{0.8.0};
chomp( my $TEMP_DIR    = "/tmp" );
chomp( my $TIME        = `date +%H%M%S` );
chomp ( my $DATE       = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
# +--------------+-------------+------+-----+---------+----------------+
# | Field        | Type        | Null | Key | Default | Extra          |
# +--------------+-------------+------+-----+---------+----------------+
# | GateId       | smallint(6) | NO   | PRI | NULL    | auto_increment |
# | IpAddress    | char(16)    | YES  |     | NULL    |                |
# | Branch       | char(3)     | YES  |     | NULL    |                |
# | Location     | char(255)   | YES  |     | NULL    |                |
# | Description  | char(255)   | YES  |     | NULL    |                |
# | LastInCount  | int(11)     | YES  |     | NULL    |                |
# | LastOutCount | int(11)     | YES  |     | NULL    |                |
# | ReverseInOut | tinyint(1)  | YES  |     | 0       |                |
# +--------------+-------------+------+-----+---------+----------------+
my $GATE_TABLE = "gate_info";
# +----------+--------------+------+-----+-------------------+----------------+
# | Field    | Type         | Null | Key | Default           | Extra          |
# +----------+--------------+------+-----+-------------------+----------------+
# | Id       | int(11)      | NO   | PRI | NULL              | auto_increment |
# | DateTime | timestamp    | NO   |     | CURRENT_TIMESTAMP |                |
# | Branch   | varchar(3)   | YES  |     | NULL              |                |
# | Total    | int(11)      | YES  |     | NULL              |                |
# | Comment  | varchar(120) | YES  |     | NULL              |                |
# +----------+--------------+------+-----+-------------------+----------------+
my $LANDS_TABLE        = "lands";
chomp( my $MSG_DATE    = `date +%Y-%m-%d` );
my $MESSAGE            = "Estimate based on counts collected from the same weekday of the previous 4 weeks. $MSG_DATE";
my $RESET_COMMENT      = "Total for this day forced to reset. $MSG_DATE";
my $SET_TOTAL_COMMENT  = "Total for this day manually set.";
my $SQL_CONFIG         = qq{/home/ils/mysqlconfigs/patroncount};
my $LOG                = "$TEMP_DIR/gatecountaudit.log";
#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [options]
$0 audits and repairs gate counts. The patron count database ocassionally will
fail to report in or include bogus gate counts. This script is designed to detect
and repair this issue.

 -a: Audit the database for broken entries and report don't fix anything.
 -c"<BRA> <YYYY-MM-DD> [<YYYY-MM-DD>]": Check date range for a specific branch. -h "CLV 2017-04-13 2017-04-20"
    The last date value is optional and will produce output for all dates since start date.
 -d: Turn on debugging.
 -f"<BRA> <ID>": Forces a branch's counts to be set to -1 for a entry in the lands table. This
    will trigger a recalculation of the counts the next time gates are repaired. See '-r'
    and '-R' for more information. A message will also be put in the comment field. To find
    a specific id see '-c'.
    Example of use: -f "CLV 225"
 -i: Interactive mode. Will ask before performing each repair.
 -m<message>: Change the comment message from the default: '$MESSAGE'.
 -R: Repair all broken entries for all the gates.
 -r<branch>: Repair broken entries for a specific branches' gates. Processes all the gates at the branch.
 -s"<BRA> <YYYY-MM-DD> <YYYY-MM-DD>": Reports the standard deviation of a given branch over a given time.
     All values are required.
 -S"<YYYY-MM-DD> <YYYY-MM-DD>": Same as '-s' but for all branches.
 -t: Preserve temporary files in $TEMP_DIR.
 -u"BRA date count [comment string]": Update a specific date for a specific branch. Branch, Date, and count
   are required, but if the comment is omitted, the message 'Total for this day manually set. \$TODAY'.
   There must already be an existing entry for the branch on the date specified.
 -U"date count [comment string]": Like -u above, but updates counts for all branches for a given date.
    This is used to set all gates to '0' for holidays. Another use might be to force all branches to '-1',
    they get a recomputed estimate based the average of the last 4 weekdays. See -R for more information.
    be computed using '-R'. Any other use would set all branches to the same gate count for the same day
    which is obviously problematic.
 -x: This (help) message.

example:
  $0 -x
  $0 -u"HVY 2018-09-02 0 Stat holiday."  # Update HVY's count for Sept. 2 to 0 because it was a stat holiday.
  $0 -c"HVY 2018-08-18 2018-09-03"       # Check the HVY counts from 2018-08-18 to 2018-09-03
  $0 -f"HVY 40816"                       # Reset the count for HVY's DB entry ID No. 40816
  $0 -U"2019-05-20 0 Stat holiday."      # Update all branches counts to '0' for a stat holiday.
  $0 -rHVY                               # Find any reset values for HVY and estimate what the count should be.
Version: $VERSION
EOF
    exit;
}

# Removes all the temp files created during running of the script.
# param:  List of all the file names to clean up.
# return: <none>
sub clean_up
{
	foreach my $file ( @CLEAN_UP_FILE_LIST )
	{
		if ( $opt{'t'} )
		{
			printf STDERR "preserving file '%s' for review.\n", $file;
		}
		else
		{
			if ( -e $file )
			{
				unlink $file;
			}
		}
	}
}

# Writes data to a temp file and returns the name of the file with path.
# param:  unique name of temp file, like master_list, or 'hold_keys'.
# param:  data to write to file.
# return: name of the file that contains the list.
sub create_tmp_file( $$ )
{
	my $name    = shift;
	my $results = shift;
	my $sequence= sprintf "%02d", scalar @CLEAN_UP_FILE_LIST;
	my $master_file = "$TEMP_DIR/$name.$sequence.$DATE.$TIME";
	# Return just the file name if there are no results to report.
	return $master_file if ( ! $results );
	open FH, ">$master_file" or die "*** error opening '$master_file', $!\n";
	print FH $results;
	close FH;
	# Add it to the list of files to clean if required at the end.
	push @CLEAN_UP_FILE_LIST, $master_file;
	return $master_file;
}

### Note: not used, but intended for profiling errors on specific gates. Coming soon.
###
# Returns the gate IDs for a named branch. The branch can be upper or lower case, and need
# not include the EPL prefix, that is branches are looked up by last three letters of the
# branches' code. Example EPLMNA can be submitted as EPLMNA, eplmna, MNA, or mna.
# param:  string code for the branch. If the argument is empty, all the branches are returned.
# return: Array of gate IDs for the branch or an empty list if the branch is misspelled or
#         doesn't exist in the database.
sub get_gate_IDs( $ )
{
	# Commands can be issued via system call as below.
	# echo "select * from gate_info;" | mysql -h mysql.epl.ca -u patroncount -p patroncount --password='somepassword'
	# Which will produce the following output.
	# GateId  IpAddress       Branch  Location        Description     LastInCount     LastOutCount    ReverseInOut
	# 1       10.1.17.135     IDY     MN      3m91200467.epl.ca       1367    395     0
	# 2       10.1.2.128      CAL     MN      3m91100462.epl.ca       282869  37640   0
	# ...
	my $branch = uc( shift );
	$branch = `echo $branch | pipe.pl -S'c0:-3'`;
	chomp $branch;
	my $results = '';
	if ( ! $branch )
	{
		$results = `echo "select GateId from $GATE_TABLE;" | mysql --defaults-file=$SQL_CONFIG -N`;
	}
	else
	{
		$results = `echo "select GateId from $GATE_TABLE where Branch='$branch';" | mysql --defaults-file=$SQL_CONFIG -N`;
	}
	printf STDERR "Search for branch submitted.\n%s", $results if ( $opt{'d'} );
	my @ids = split '\n', $results;
	# remove the header from the returned table that describes the columns.
	shift @ids if ( @ids );
	return @ids;
}

# Returns a list of all the branches in the lands table.
# param:  none.
# return: Array list of all the branches in the lands table.
sub get_all_branches()
{
	my $results = `echo "select distinct Branch from $LANDS_TABLE;" | mysql --defaults-file=$SQL_CONFIG -N`;
	my @branch_ids = split '\n', $results;
	# remove the header from the returned table that describes the columns.
	shift @branch_ids if ( @branch_ids );
	return @branch_ids;
}

# Repairs any erroneous entries for a given branch. This function makes repairs to the LANDS table
# which contains aggregate data from all gates at a given branch for a specific date.
# TODO define error types fully. Example find entries that are -1, those indicate that there was
# a hardware or network error at the time of polling. Other errors are more subtle. A regular gate
# count appearing on a date that is marked as a branch holiday indicates artificially high readings.
# Counts that have dropped unexplainedly are another type of error, which can manifest in the LANDS
# table, but are best dealt with by profiling individual gates.
# param:  Branch code as a string.
# return: Number of errors fixed.
sub repair_branch_counts( $ )
{
	my $branch = shift;
	my $repair_counts = repair_incomplete_polling_results( $branch );
	# Other repairs as required.
	return $repair_counts;
}

# Repairs any erroneous entries that are -1, those indicate that there was
# a hardware or network error at the time of polling.
# param:  Branch code as a string.
# return: Number of errors fixed.
sub repair_incomplete_polling_results( $ )
{
	my $branch       = shift;
	return 0 if ( ! $branch );
	my $repair_count = 0;
	# Consider the following errors for 'WMC'.
	# +-------+---------------------+--------+-------+---------+
	# | Id    | DateTime            | Branch | Total | Comment |
	# +-------+---------------------+--------+-------+---------+
	# |   ...
	# |  9867 | 2014-03-23 23:58:01 | WMC    |    -1 | NULL    |
	# | 10379 | 2014-04-24 23:58:02 | WMC    |    -1 | NULL    |
	# |   ...
	# We note that the entry with ID 10379 took place on 2014-04-24 23:58:02, so we select
	# the previous 28 days worth of entries which will necessarily include the last 4 week
	# days prior to the day the error occured.
	# This finds all the network errors for a given branch.
	my $results = `echo 'select * from $LANDS_TABLE where Total < 0 and Branch = "$branch" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
	my $branch_errors = create_tmp_file( "gatecountaudit_branch_errors", $results );
	return $repair_count if ( ! -s $branch_errors );
	$results = `cat $branch_errors | pipe.pl -W'\\s+' -oc0`;
	my $branch_error_Ids = create_tmp_file( "gatecountaudit_branch_error_Ids", $results );
	return $repair_count if ( ! -s $branch_error_Ids );
	# Open that tmp file and read line by line the Ids then fix them.
	open ID_FILE, "<$branch_error_Ids" or die "** error expected a temp file of Ids that have errors for $branch, $!\n";
	while (<ID_FILE>)
	{
		chomp( my $primary_key_Id = $_ );
		$primary_key_Id = sprintf "%d", $primary_key_Id;
		# +-------+---------------------+--------+-------+---------+
		# | Id    | DateTime            | Branch | Total | Comment |
		# +-------+---------------------+--------+-------+---------+
		# | 10363 | 2014-04-23 23:58:01 | WMC    |  1441 | NULL    | Monday
		# | 10347 | 2014-04-22 23:58:01 | WMC    |  1800 | NULL    |
		# | 10331 | 2014-04-21 23:58:01 | WMC    |     0 | NULL    |
		# | 10315 | 2014-04-20 23:58:01 | WMC    |     0 | NULL    |
		# | 10299 | 2014-04-19 23:58:01 | WMC    |  1716 | NULL    |
		# | 10283 | 2014-04-18 23:58:01 | WMC    |     0 | NULL    |
		# | 10267 | 2014-04-17 23:58:01 | WMC    |  1536 | NULL    | <- Previous Sunday
		# | 10251 | 2014-04-16 23:58:02 | WMC    |  1302 | NULL    |
		# | 10235 | 2014-04-15 23:58:01 | WMC    |  1078 | NULL    |
		# | 10219 | 2014-04-14 23:58:02 | WMC    |  1421 | NULL    |
		# | 10203 | 2014-04-13 23:58:01 | WMC    |   865 | NULL    |
		# | 10187 | 2014-04-12 23:58:01 | WMC    |  1674 | NULL    |
		# | 10171 | 2014-04-11 23:58:01 | WMC    |  1024 | NULL    |
		# | 10155 | 2014-04-10 23:58:02 | WMC    |  1349 | NULL    | <- Previous Sunday
		# | 10139 | 2014-04-09 23:58:01 | WMC    |  1483 | NULL    |
		# | 10123 | 2014-04-08 23:58:01 | WMC    |  1433 | NULL    |
		# | 10107 | 2014-04-07 23:58:01 | WMC    |  1541 | NULL    |
		# | 10091 | 2014-04-06 23:58:01 | WMC    |   905 | NULL    |
		# | 10075 | 2014-04-05 23:58:01 | WMC    |  1780 | NULL    |
		# | 10059 | 2014-04-04 23:58:01 | WMC    |  1417 | NULL    |
		# | 10043 | 2014-04-03 23:58:01 | WMC    |  1658 | NULL    | <- Previous Sunday
		# | 10027 | 2014-04-02 23:58:01 | WMC    |  1850 | NULL    |
		# | 10011 | 2014-04-01 23:58:01 | WMC    |  1678 | NULL    |
		# |  9995 | 2014-03-31 23:58:01 | WMC    |  1723 | NULL    |
		# |  9979 | 2014-03-30 23:58:01 | WMC    |   895 | NULL    |
		# |  9963 | 2014-03-29 23:58:01 | WMC    |  1792 | NULL    |
		# |  9947 | 2014-03-28 23:58:01 | WMC    |  1272 | NULL    |
		# |  9931 | 2014-03-27 23:58:02 | WMC    |  1390 | NULL    | <- Previous Sunday
		# +-------+---------------------+--------+-------+---------+
		# Note that some of the selections will eventually use an average estimate in it's own estimate but
		# the data should smooth naturally as as repair older entries then newer ones.
		# Select out these value and then take an average. (1536 + 1349 + 1658 + 1390) / 4 = 1483.25 or 1484.
		# Select 30 samples from this branch earlier than the date on the entry with the Id we are going to fix.
		$results = `echo 'select * from $LANDS_TABLE where Id<$primary_key_Id and Branch = "$branch" order by DateTime desc limit 30;' | mysql --defaults-file=$SQL_CONFIG -N | pipe.pl -W'\\s+'`;
		my $branch_all_previous_month_counts = create_tmp_file( "gatecountaudit_all_prev_month_counts", $results );
		next if ( ! -s $branch_all_previous_month_counts );
		$results = `cat $branch_all_previous_month_counts | pipe.pl -Lskip7`;
		my $branch_previous_count_samples = create_tmp_file( "gatecountaudit_prev_count_samples", $results );
		if ( ! -s $branch_previous_count_samples )
		{
			printf STDERR "* warning, unable to collect enough data to estimate counts for %s.\n", $branch;
			next;
		}
		# 10283|2014-04-18|23:58:01|WMC|0|NULL
		# 10171|2014-04-11|23:58:01|WMC|1024|NULL
		# 10059|2014-04-04|23:58:01|WMC|1417|NULL
		# 9947|2014-03-28|23:58:01|WMC|1272|NULL
		# Now pipe can take an average and report to STDERR. We don't need the results from STDOUT.
		`cat $branch_previous_count_samples | pipe.pl -vc4 2>err.txt`;
		next if ( ! -e "err.txt" );
		# Now parse the STDERR report.
		$results = `cat err.txt | pipe.pl -W'\\s+' -oc1 -g'c1:\\d+'`;
		if ( -e "err.txt" )
		{
			unlink "err.txt" ;
		}
		chomp( $results );
		return $repair_count if ( ! $results );
		my $average_previous_days = sprintf "%d", $results;
		# If we got some weird result report it and continue.
		if ( $average_previous_days <= 0 )
		{
			printf STDERR "* warning, cowardly refusing to update $branch count, Id %s with %s\n", $primary_key_Id, $average_previous_days;
		}
		else
		{
			printf STDERR "updating $branch count, Id %s with %s\n", $primary_key_Id, $average_previous_days;
			if ( $opt{'i'} )
			{
				printf STDERR "do you want to continue? ";
				my $answer = <>;
				next if ( $answer =~ m/(n|N)/ );
			}
			# Updating then becomes
			`echo 'update $LANDS_TABLE set Total=$average_previous_days, Comment="$MESSAGE" where Id=$primary_key_Id;' | mysql --defaults-file=$SQL_CONFIG -N >>update_err.txt`;
			$repair_count++;
		}
	}
	close ID_FILE;
	return $repair_count;
}

# Audits the database for missing data. Specificially the LANDS table is checked for
# negative values that indicate a given gate could not be reached at the time of checkin.
# param:  none
# return: none
sub do_audit()
{
	# we have to get all the branches.
	my @branches = get_all_branches();
	foreach my $branch ( @branches )
	{
		printf STDERR "branch ->%s\n", $branch if ( $opt{'d'} );
		# Select all the entries for this branch by date range.
		my $results = `echo 'select * from lands where Branch="$branch" and Total<0 order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
		printf "%s", $results;
	}
}

# Reports gate counts from a specific day. This can be used as a spot check.
# param:  branch code like 'CLV' start date <yyyy-mm-dd> optional end date <yyyy-mm-dd> "CLV 2017-04-13 2017-04-20".
# return: none
sub get_branch_counts_by_date( $ )
{
	# Check the date submitted for conformance with 'yyyy-mm-dd' format.
	my ( $branch, $start_date, $end_date ) = split '\s+', shift;
	printf "branch ->%s\n", $branch if ( $opt{'d'} );
	my $results = '';
	if ( $start_date =~ m/^\d{4}\-\d{2}\-\d{2}$/ )
	{
		$results = `echo 'select * from lands where Branch="$branch" and DateTime>="$start_date" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
	}
	else
	{
		printf STDERR "** error: invalid start date provided '%s'.\n", $start_date;
		usage();
	}
	if ( $end_date )
	{
		if ( $end_date =~ m/^\d{4}\-\d{2}\-\d{2}$/ )
		{
			$results = `echo 'select * from lands where Branch="$branch" and DateTime>="$start_date" and DateTime<="$end_date" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
		}
		else
		{
			printf STDERR "** error: invalid end date provided '%s'.\n", $end_date;
			usage();
		}
	}
	printf "%s", $results;
}

# Resets gate counts in the lands table for a specific day, and adds a comment to that affect in the comments field.
# When '-r', or '-R' are rerun the gate counts for that day will be estimated.
# param:  branch code like 'CLV' start date <yyyy-mm-dd> like "CLV 2017-04-13".
# return: none
sub reset_branch_counts_by_date( $ )
{
	# Check the date submitted for conformance with 'yyyy-mm-dd' format.
	my ( $branch, $lands_id ) = split '\s+', shift;
	printf "branch ->%s\n", $branch if ( $opt{'d'} );
	printf "lands_id ->%s\n", $lands_id if ( $opt{'d'} );
	my $results = '';
	if ( $lands_id =~ m/^\d{3,}$/ )
	{
		$results = `echo 'select * from lands where Branch="$branch" and Id="$lands_id";' | mysql --defaults-file=$SQL_CONFIG -N`;
		my $query = sprintf "update lands set Total=-1, Comment='%s' where Branch='%s' and Id=%d;", $RESET_COMMENT, $branch, $lands_id;
		printf "query ->%s\n", $query if ( $opt{'d'} );
		$results = `echo "$query" | mysql --defaults-file=$SQL_CONFIG -N`;
	}
	else
	{
		printf STDERR "** error: invalid lands table Id provided '%s'.\n", $lands_id;
		usage();
	}
	printf "%s", $results;
}

# Kicks off the setting of various switches.
# param:
# return:
sub init
{
    my $opt_string = 'ac:df:im:Rr:s:S:tu:U:x';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	if ( $opt{'m'} )
	{
		$MESSAGE = $opt{'m'}." $MSG_DATE";
		printf STDERR "Comment message set to '%s'.\n", $MESSAGE;
	}
}

# Computes standard deviation of a argument list.
# param:  list of values.
# return: standard deviation of supplied values.
sub compute_stddev
{
	my @sample = @_;
	my $count  = scalar @sample;
	my $sum    = 0;
	return 0 if ( $count == 0 ); # No counts for this branch in the specified date range.
	foreach my $i ( @sample )
	{
		next if ( $i !~ m/^(\-)?\d+(\.\d+)?$/ );
		$sum += $i;
	}
	my $avg = $sum / $count;
	printf STDERR "average: '%s'/'%s' = '%s'\n", $sum, $count, $avg if ( $opt{'d'} );
	$sum = 0;
	foreach my $i ( @sample )
	{
		next if ( $i !~ m/^(\-)?\d+(\.\d+)?$/ );
		$sum += (( $i - $avg ) ** 2);
	}
	my $variance = $sum / $count;
	my $stddev   = sqrt $variance;
	printf STDERR "variance: '%s' and stddev='%s'\n", $variance, $stddev if ( $opt{'d'} );
	return $stddev;
}

# Compute the standard deviation of a given branch's.
# param:  string of branch code (3 chars) and 2 dates that act as a range. Example:
# return: none.
sub compute_branch_error( $ )
{
	# Check the date submitted for conformance with 'yyyy-mm-dd' format.
	my ( $branch, $start_date, $end_date ) = split '\s+', shift;
	printf "branch ->%s\n", $branch if ( $opt{'d'} );
	my $results = '';
	if ( $start_date =~ m/^\d{4}\-\d{2}\-\d{2}$/ )
	{
		$results = `echo 'select Total from lands where Branch="$branch" and DateTime>="$start_date" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
	}
	else
	{
		printf STDERR "** error: invalid start date provided '%s'.\n", $start_date;
		usage();
	}
	if ( $end_date )
	{
		if ( $end_date =~ m/^\d{4}\-\d{2}\-\d{2}$/ )
		{
			$results = `echo 'select Total from lands where Branch="$branch" and DateTime>="$start_date" and DateTime<="$end_date" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N`;
		}
		else
		{
			printf STDERR "** error: invalid end date provided '%s'.\n", $end_date;
			usage();
		}
	}
	my @samples = split '\n', $results;
	printf "%s: %8.2f\n", $branch, compute_stddev( @samples );
}

# Sets an arbitrary but specific branch's count to a specific value 
# for a specific date, and adds a comment with an automatically computed
# date.
# param:  Array of words "{branch} {date} {count} {many comment words}"
# return: count of updates made.
sub set_branch_date_count_comment( $ )
{
    my $repairs = 0;
    my ( $branch, $date, $count, @comment_words ) = split '\s+', shift;
    my $comment = join( ' ', @comment_words );
	if ( ! defined $branch || ! defined $date || ! defined $count )
	{
		printf STDERR "** error one or more fields are empty.\n";
		return $repairs;
	}
	# Now add them but make sure there is an entry for that branch and date.
	my $date_search = $date . '%';
	my $entry_id = `echo 'SELECT Id FROM lands WHERE Branch="$branch" and DateTime LIKE "$date_search%" order by DateTime;' | mysql --defaults-file=$SQL_CONFIG -N 2>>$LOG`;
	chomp $entry_id;
	if ( ! defined $entry_id || ! $entry_id )
	{
		printf STDERR "** error no entry for '%s' on date %s.\n", $branch, $date;
		return $repairs;
	}
	$comment = $SET_TOTAL_COMMENT if ( ! defined $comment );
	printf STDERR "%s %s %s %s\n", $branch, $date, $count, $comment;
	# UPDATE lands SET Total=397,Comment="Value entered hand recorded values June 1, 2018" WHERE Id=38264;
	my $results = `echo 'UPDATE lands SET Total=$count,Comment="$comment $MSG_DATE" WHERE Id=$entry_id;' | mysql --defaults-file=$SQL_CONFIG -N 2>>$LOG`;
	print `echo 'SELECT * FROM lands WHERE Id=$entry_id;' | mysql --defaults-file=$SQL_CONFIG 2>>$LOG`;
	return $repairs++;
}

init();
my $repairs = 0;
### code starts
if ( $opt{'a'} )
{
	do_audit();
}
if ( $opt{'c'} )
{
	# Check a specific day for high counts, these gates may need to be cleaned or checked if
	# the gate reads large values on days when the branch is closed.
	get_branch_counts_by_date( $opt{'c'} );
}
if ( $opt{'f'} )
{
	reset_branch_counts_by_date( $opt{'f'} );
}
if ( $opt{'r'} )
{
	$repairs += repair_branch_counts( $opt{'r'} );
}
if ( $opt{'R'} )
{
	my @all_branches = get_all_branches();
	foreach my $branch ( @all_branches )
	{
		$repairs += repair_branch_counts( $branch );
	}
}
if ( $opt{'s'} )
{
	compute_branch_error( $opt{'s'} );
}
if ( $opt{'S'} )
{
	my $results = `echo 'select GateId, Branch from gate_info;' | mysql --defaults-file=$SQL_CONFIG -N`;
	my @branches =  get_all_branches();
	foreach my $branch ( @branches )
	{
		printf STDERR "branch: '%s'\n", $branch if ( $opt{'d'} );
		my $s = $branch . " " . $opt{'S'};
		compute_branch_error( $s );
	}
}
if ( $opt{'u'} )
{
	# -u"BRA date count unquoted comment string..."
	$repairs += set_branch_date_count_comment( $opt{'u'} );
}
if ( $opt{'U'} )
{
    my @branches = get_all_branches();
    foreach my $branch ( @branches )
    {
        # -U"date count unquoted comment string..."
        if ( $branch )
        { 
            my $param_string = $branch . " " . $opt{'U'};
            printf STDERR "message: '%s'\n", $param_string if ( $opt{'d'} );
            $repairs += set_branch_date_count_comment( $param_string );
        }
    }
}
printf STDERR "Total repairs: %d\n", $repairs if ( $opt{'d'} );
### code ends

clean_up();
# EOF
