Project Notes
-------------
Initialized: Sat Sep  3 08:28:52 MDT 2016.
1. EPL failed its gate count audit with the city because error correction methodology could not reproduced using the algorithm described in our documentation. Pilar has asked Soleil for a report by the end of the week outlining what we are going to do about gate counts going forward, and I provided the following recommendations to address the technical concerns.
2a. If the gate is unreachable at the last pole of the day, the counts from the previous 4 week days will be averaged and the LANDS table will be amended to include this value and a comment indicating it is an estimate value. Staff web uses the LANDS table as its data source. These are identified by Total=-1 in the lands table.
2b. If the network is unavailable at the time of polling there will be no entry for a given date. An example is given below.
```
+-------+---------------------+--------+-------+----------------------------------------------------+
| Id    | DateTime            | Branch | Total | Comment                                            |
+-------+---------------------+--------+-------+----------------------------------------------------+
| 26138 | 2016-09-06 23:57:31 | MCN    |   159 | NULL                                               |
| 26114 | 2016-09-05 23:57:31 | MCN    |   325 | NULL                                               |
| 26092 | 2016-09-03 23:57:37 | MCN    |   103 | NULL                                               |
| 26061 | 2016-09-02 23:57:38 | MCN    |   155 | NULL                                               |
```
In this case the missing entry manifests as double normal daily average because the day after the outage the gate will compute the daily total based on the previous day which was actually 2 days ago. In this case the missing date shall be identified and a value inserted into the lands table to ensure temporal consistency. The algorithm that does this should be run before any others, and should follow the same design as the one used in 2a.
2c. If a gate reports counts on a branch holiday, the script should set the count to 0 and record the reported value in the comment field for further analysis. Staff should be notified via email.
3. If a gate reports 50% above average or more for a given period of time, staff should be emailed of the unusual condition as it may require investigation.
4. A dashboard visualization should be created to show trending counts compared to daily counts so we can quickly diagnose gate count problems and trends over time.
5. Document the above, and any other related policies and procedures.

Instructions for Running:
```
gatecountaudit.pl -x
```

Product Description:
--------------------
Perl script written by Andrew Nisbet for Edmonton Public Library, distributable by the enclosed license.

Repository Information:
-----------------------
This product is under version control using Git.
[Visit GitHub](https://github.com/Edmonton-Public-Library)

Dependencies:
-------------
[pipe.pl](https://github.com/anisbet/pipe)
getpathname


Known Issues:
-------------
None
