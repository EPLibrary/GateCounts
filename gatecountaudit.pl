#!/usr/bin/perl -w
####################################################
#
# Perl source file for project gatecountaudit 
#
# Finds and repairs bad gate counts in patron count database.
#    Copyright (C) 2016  Andrew Nisbet
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
#          0.3.01 - Fix usage. 
#          0.3 - Fix loop bug. 
#          0.2 - Repair (-R) tested add audit - find missing entries. 
#          0.1 - Repair (-r) tested. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

my $VERSION            = qq{0.3.01};
chomp( my $TEMP_DIR    = "/tmp" );
chomp( my $TIME        = `date +%H%M%S` );
chomp ( my $DATE       = `date +%Y%m%d` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
my $PIPE               = "/usr/local/sbin/pipe.pl";
my $PASSWORD_FILE      = "password.txt";
my $USER               = "";
my $DATABASE           = "";
my $PASSWORD           = "";
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
my $MESSAGE            = "Estimate based on previous 4 week days. $MSG_DATE";

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-adim<comment>tRr<branch>tx]
$0 audits and repairs gate counts. The patron count database ocassional.

 -a: Audit the database for broken entries and report don't fix anything.
 -d: Turn on debugging.
 -i: Interactive mode. Will ask before performing each repair. 
 -m<message>: Change the comment message from the default: '$MESSAGE'.
 -t: Preserve temporary files in $TEMP_DIR.
 -R: Repair all broken entries for all the gates.
 -r<branch>: Repair broken entries for a specific branches' gates. Processes all the gates at the branch.
 -x: This (help) message.

example:
  $0 -x
Version: $VERSION
EOF
    exit;
}

# Reads a password file and parses out the database, user name, and password.
# The format of the file is one line that is uncommented ('#' is the comment character)
# where the columns are separated by colons ':'. 
# Example: database_name:password:database_login
# The variables $DATABASE, $PASSWORD, and $USER are populated before returning.
# Make sure you don't include any extra spaces on any of the fields.
# param:  File name.
# return: none.
sub read_password( $ )
{
	my $password_file = shift;
	my @return_list = ();
	open FH, "<$password_file" or die "*** error opening password file '$password_file', $!\n";
	while( <FH> )
	{
		my $line = $_;
		chomp $line;
		next if ( $line =~ m/(\s+)?#/ );
		@return_list = split ':', $line;
		$DATABASE = $return_list[0];
		$PASSWORD = $return_list[1];
		$USER     = $return_list[2];
		# exit after we have read the first line that isn't a comment.
		last;
	}
	close FH;
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
	$branch = `echo $branch | $PIPE -S'c0:-3'`;
	chomp $branch;
	my $results = '';
	if ( ! $branch )
	{
		$results = `echo "select GateId from $GATE_TABLE;" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
	}
	else
	{
		$results = `echo "select GateId from $GATE_TABLE where Branch='$branch';" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
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
	my $results = `echo "select distinct Branch from $LANDS_TABLE;" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
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
	my $results = `echo 'select * from $LANDS_TABLE where Total < 0 and Branch = "$branch" order by DateTime;' | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD" | $PIPE -L2-`;
	my $branch_errors = create_tmp_file( "gatecountaudit_branch_errors", $results );
	return $repair_count if ( ! -s $branch_errors );
	$results = `cat $branch_errors | $PIPE -W'\\s+' -oc0 -L2-`;
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
		$results = `echo 'select * from $LANDS_TABLE where Id<$primary_key_Id and Branch = "$branch" order by DateTime desc limit 30;' | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD" | $PIPE -W'\\s+' -L2-`;
		my $branch_all_previous_month_counts = create_tmp_file( "gatecountaudit_all_prev_month_counts", $results );
		next if ( ! -s $branch_all_previous_month_counts );
		$results = `cat $branch_all_previous_month_counts | $PIPE -Lskip7`;
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
		`cat $branch_previous_count_samples | $PIPE -vc4 2>err.txt`;
		next if ( ! -e "err.txt" );
		# Now parse the STDERR report.
		$results = `cat err.txt | $PIPE -W'\\s+' -oc1 -g'c1:\\d+'`;
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
			`echo 'update $LANDS_TABLE set Total=$average_previous_days, Comment="$MESSAGE" where Id=$primary_key_Id;' | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD" >>update_err.txt`;
			$repair_count++;
		}
	}
	close ID_FILE;
	return $repair_count;
}

# Audits the database for missing data. Specificially the LANDS table is checked for 
# negative values that indicate a given gate could not be reached at the time of checkin.
# The 
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
		my $results = `echo 'select * from lands where Branch="$branch" and Total<0;' | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
		printf "%s", $results;
	}
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'adim:tRr:x';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	read_password( $PASSWORD_FILE );
	printf STDERR "Database: %s, Password: '********', Login: %s.\n", $DATABASE, $USER if ( $opt{'d'} );
	if ( $opt{'m'} )
	{
		$MESSAGE = $opt{'m'}." $MSG_DATE";
		printf STDERR "Comment message set to '%s'.\n", $MESSAGE;
	}
}

init();
my $repairs    = 0;
### code starts
if ( $opt{'a'} )
{
	do_audit();
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
printf STDERR "Total repairs: %d\n", $repairs if ( $opt{'d'} );
### code ends

clean_up();
# EOF
