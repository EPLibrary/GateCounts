Project Notes
-------------
Initialized: Sat Sep  3 08:28:52 MDT 2016.
1. EPL failed its gate count audit with the city because error correction methodology could not reproduced using the algorithm described in our documentation. Pilar has asked Soleil for a report by the end of the week outlining what we are going to do about gate counts going forward, and I provided the following recommendations to address the technical concerns.
2. If the gate is unreachable at the last pole of the day, the counts from the previous 4 week days will be averaged and the LANDS table will be amended to include this value and a comment indicating it is an estimate value. Staff web uses the LANDS table as its data source.
3. If a gate reports counts on a branch holiday, the script should set the count to 0 and record the reported value in the comment field for further analysis. Staff should be notified via email.
4. If a gate reports 50% above average or more for a given period of time, staff should be emailed of the unusual condition as it may require investigation.
5. A dashboard visualization should be created to show trending counts compared to daily counts so we can quickly diagnose gate count problems and trends over time.
6. Document the above, and any other related policies and procedures.

Instructions for Running:
```
./$1.pl -x
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
