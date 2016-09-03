#!/usr/bin/perl -w
####################################################
#
# Perl source file for project gatecountaudit 
#
# <one line to give the program's name and a brief idea of what it does.>
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
#          0.0 - Dev. 
#
####################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

my $VERSION            = qq{0.0};
chomp( my $TEMP_DIR    = "/tmp" );
chomp( my $TIME        = `date +%H%M%S` );
chomp ( my $DATE       = `date +%m/%d/%Y` );
my @CLEAN_UP_FILE_LIST = (); # List of file names that will be deleted at the end of the script if ! '-t'.
my $PIPE               = "/usr/local/sbin/pipe.pl";
my $PASSWORD_FILE      = "password.txt";
my $USER               = "";
my $DATABASE           = "";
my $PASSWORD           = "";

#
# Message about this program and how to use it.
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-xt]
Usage notes for gatecountaudit.pl.

 -a: Audit the database for broken entries and report don't fix anything. (See -u and -U).
 -d: Turn on debugging.
 -t: Preserve temporary files in $TEMP_DIR.
 -U: Repair all broken entries.
 -u<Gate_ID>: Repair broken entries for a specific gate.
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

# Returns the gate IDs for a named branch. The branch can be upper or lower case, and need
# not include the EPL prefix, that is branches are looked up by last three letters of the 
# branches' code. Example EPLMNA can be submitted as EPLMNA, eplmna, MNA, or mna.
# param:  string code for the branch.
# return: Array of gate IDs for the branch or an empty list if the branch is misspelled or 
#         doesn't exist in the database.
sub get_gate_IDs( $ )
{
	my $branch = uc( shift );
	my @ids = ();
	if ( ! $branch )
	{
		printf STDERR "** requested branch is empty or undefined.\n";
		return @ids;
	}
	printf STDERR "Search for branch '$branch' submitted.\n", $branch if ( $opt{'d'} );
	@ids = `echo "select GateId from gate_info where Branch='$branch';" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
	return @ids;
}

# Audits the database for missing data. Specificially the LANDS table is checked for 
# negative values that indicate a given gate could not be reached at the time of checkin.
# The 
# param:  none
# return: none
sub do_audit()
{
	# Commands can be issued via system call as below.
	# echo "select * from gate_info;" | mysql -h mysql.epl.ca -u patroncount -p ^Ctroncount --password='ub2up@1thbtx'
	# Which will produce the following output.
	# GateId  IpAddress       Branch  Location        Description     LastInCount     LastOutCount    ReverseInOut
	# 1       10.1.17.135     IDY     MN      3m91200467.epl.ca       1367    395     0
	# 2       10.1.2.128      CAL     MN      3m91100462.epl.ca       282869  37640   0
	# 3       10.1.2.121      CAL     MN      3m91100463.epl.ca       90      1054    0
	# 4       10.1.15.112     WOO     MN      3m91100498.epl.ca       26638   409959  0
	# 5       10.1.15.111     WOO     MN      3m91100499.epl.ca       27669   956     0
	# 6       10.1.11.129     RIV     MN      3m91100500.epl.ca       28444   10277   0
	# 7       10.1.11.128     RIV     MN      3m91100501.epl.ca       72658   92311   0
	# 8       10.1.13.118     SPW     MN      3m91200468.epl.ca       13706   6471    0
	# 9       10.1.12.122     STR     MN      3m91100497.epl.ca       10576   9466    0
	# 10      10.1.12.128     STR     MN      3m91200508.epl.ca       230432  80629   0
	# 11      10.1.9.141      LON     MN      3m91100507.epl.ca       1718    3851    0
	# 12      10.1.9.126      LON     MN      3m91200506.epl.ca       340526  305469  0
	# 13      10.2.20.132     MNA     WE      3m91200174.epl.ca       1671243 1656886 0
	# 14      10.2.20.113     MNA     EA      3m91100057.epl.ca       863980  1106981 0
	# 15      10.2.20.131     MNA     JU      3m91100175.epl.ca       144554  158122  0
	# 16      10.2.14.175     WMC     MN      3m91200210.epl.ca       154313  140941  0
	# 17      10.2.14.183     WMC     MN      3m91200213.epl.ca       4500    3726    0
	# 18      10.1.16.156     LHL     MN      3m91200170.epl.ca       760033  785363  0
	# 19      10.2.3.146      CPL     MN      3m91200464.epl.ca       208398  208596  0
	# 20      10.2.4.133      CSD     MN      3m91100466.epl.ca       19719   362117  0
	# 21      10.2.4.135      CSD     MN      3m91100465.epl.ca       353101  16997   0
	# 29      10.2.5.128      CLV     MN      3m91202275.epl.ca       414149  403246  0
	# 24      10.1.1.160      MLW     EA      3M91200204.epl.ca       810182  809805  0
	# 25      10.1.18.112     ABB     MN      3m91200461.epl.ca       200281  203712  0
	# 26      10.1.7.126      JPL     MN      3M91200171.epl.ca       124476  125210  0
	# 27      10.1.6.122      HIG     MN      3M91202028.epl.ca       74122   77366   0
	# 28      10.2.8.129      MEA     MN      3M91201585.epl.ca       390296  498313  0
	# 30      10.2.10.127     WHP     MN      3M9110502.epl.ca        2703    2668    0
	# 31      10.2.19.123     MCN     MN      3M91100503.epl.ca       16623   16884   0
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'adtUu:x';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ( $opt{'x'} );
	# Test functions
	read_password( $PASSWORD_FILE );
	printf STDERR "Database: %s, Password: ********, Login: %s.\n", $DATABASE, $PASSWORD, $USER if ( $opt{'d'} );
	my @gate_ids = get_gate_IDs( "EPLMNA" );
	printf STDERR "requested gate ids: %d\n", scalar( @gate_ids );
}

init();
my $is_audited = 0;
my $repairs    = 0;
### code starts
if ( $opt{'a'} )
{
	do_audit();
	$is_audited++;
}
if ( $opt{'u'} )
{
	do_audit() if ( ! $is_audited );
	$is_audited++;
	$repairs += repair_entries( $opt{'U'} );
}
if ( $opt{'U'} )
{
	do_audit() if ( ! $is_audited );
	$is_audited++;
	$repairs = repair_entries( $opt{'U'} );
}
### code ends

clean_up();
# EOF
