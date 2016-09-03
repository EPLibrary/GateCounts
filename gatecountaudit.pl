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
 -U: Repair all broken entries for all the gates.
 -u<branch>: Repair broken entries for a specific branches' gates. Processes all the gates at the branch.
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
		$results = `echo "select GateId from gate_info;" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
	}
	else
	{
		$results = `echo "select GateId from gate_info where Branch='$branch';" | mysql -h mysql.epl.ca -u $USER -p $DATABASE --password="$PASSWORD"`;
	}
	printf STDERR "Search for branch submitted.\n%s", $results if ( $opt{'d'} );	
	my @ids = split '\n', $results;
	# remove the header from the returned table that describes the columns.
	shift @ids if ( @ids );
	return @ids;
}

# Repairs any erroneous entries to some definition of erroneous. TODO define error types fully.
# param:  Gate id string.
# return: Number of errors fixed.
sub repair_gates_by_gate_id( $ )
{
	return 0; # Stub for now.
}

# Audits the database for missing data. Specificially the LANDS table is checked for 
# negative values that indicate a given gate could not be reached at the time of checkin.
# The 
# param:  none
# return: none
sub do_audit()
{
	
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
	printf STDERR "Database: %s, Password: ********, Login: %s.\n", $DATABASE, $USER if ( $opt{'d'} );
	my @gate_ids = get_gate_IDs( "eplclv" );
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
	my @gates = get_gate_IDs( $opt{'u'} );
	foreach my $gate ( @gates )
	{
		$repairs += repair_gates_by_gate_id( $gate );
	}
}
if ( $opt{'U'} )
{
	do_audit() if ( ! $is_audited );
	$is_audited++;
	my @all_branches = get_all_branches();
	foreach my $branch ( @all_branches )
	{
		my @gates = get_gate_IDs( $branch );
		foreach my $gate ( @gates )
		{
			$repairs += repair_gates_by_gate_id( $gate );
		}
	}
}
printf STDERR "Total repairs: %d\n", $repairs if ( $opt{'d'} );
### code ends

clean_up();
# EOF
