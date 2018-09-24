#!/bin/bash
# Typically gate counts, for now, are cut and pasted from a spreadsheet. Here is an example:
# ''' console
# $ cat delete.me.hvy.raw
# 6/19/2018       17744   16012           363
# 6/20/2018       18191   16403           447
# 6/21/2018       18733   16901           542
# 6/22/2018       19015   17162           282
# 6/23/2018       19649   17757   Sat     634
# 6/24/2018       19934   18021   Sun     285
# 6/25/2018       20350   18384           416
# 6/26/2018       20795   18764           445
# 6/27/2018       21148   19080           353
# 6/28/2018       21645   19521           497
# 6/29/2018       22069   19899           424
# 6/30/2018       22468   20263   Sat     399
# '''
if [ $# -lt 1 ]; then
    echo "Usage: $0 {BRA}" >&2
    echo " Takes a branch 3 character code and looks for a file named" >&2
    echo " {bra}.raw. If one exists, it processes the values in the file into a script" >&2
    echo " that, if run, will update that specific branches counts." >&2
    echo " The raw input file can be cut and pasted from a spread sheet that is organized as follows." >&2
    echo " Date            In      out             Delta from yesterday" >&2
    echo " 6/19/2018       17744   16012    Sat    363" >&2
    echo " 6/20/2018       18191   16403           447" >&2
    echo " 6/21/2018       18733   16901    Mon    542" >&2
    exit 1
fi
branch=$(echo $1 | pipe.pl -tc0) 
BRANCH=$(echo $1 | pipe.pl -tc0 -ec0:uc) 
OUTFILE=update.$branch.`date +%Y%m%d`.sh
# If you want to make a temp script to update these values in the database heres the pipe command.
# Explaination:
## pipe-1: Split the input by whitespace and '/' in the date field. Pad the month with leading '0' (should do same for month), order the output so the year then month then day then everything else. '''2018|06|19|17744|16012|363'''
## pipe-2: Since someone put in a extra field in some cases (like Sat), find all just the lines that don't have a sixth field and add the word 'day', then the rest of field 5. '''2018|06|19|17744|16012|day|363'''
## pipe-3: Add hyphens to the month and day fields, then paste c0,c1,c2 together into a date field, and output only the date field and count. '''2018-06-19|363'''
## pipe-4: Mask the 2 fields so they read like a command to gatecountaudit, and output to the temp file script name. '''gatecountaudit.pl -bHVY -u'2018-06-30 399' '''
cat $branch.raw | pipe.pl -W'\/|\s+' -pc0:2.0,c1:2.0 -oc2,c0,c1,remaining | pipe.pl -Zc6 -i -mc5:"day\|#" | pipe.pl -mc1:-#,c2:-# -Oc0,c1,c2 -oc0,c6 | pipe.pl -mc0:"gatecountaudit.pl -u'$BRANCH #",c1:" #####'" -h' ' >$OUTFILE
echo "from the command line:" >&2
echo "bash $OUTFILE" >&2
# EOF
