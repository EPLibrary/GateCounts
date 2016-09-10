####################################################
# Makefile for project deleteme 
# Created: Sat Sep  3 08:28:52 MDT 2016
#
# Manages building the gatecountaudit application.
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
# Written by Andrew Nisbet at Edmonton Public Library
# Rev: 
#      0.0 - Dev. 
####################################################
# This application runs native on ILSdev1@epl.ca and should be scheduled from there.
LOCAL=~/projects/gatecountaudit/
APP=gatecountaudit.pl
ARGS=-rABB -tdi
.PHONY: test head clean
test:
	perl -c ${APP}
	${LOCAL}${APP} ${ARGS}
	-head /tmp/gatecountaudit_*
clean:
	-rm /tmp/gatecountaudit_*

