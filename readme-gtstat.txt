/*  GTSTAT - Filters and converts to human readable form the file 'GUN-TACTYX-results.txt'
 *  Copyright (C) 2004  Tobi Vollebregt
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 *
 *  Tobi Vollebregt
 *  tobi_v@users.sourceforge.net
 */



                    August 31th 2004
INDEX

1 - What is this?
2 - Usage
3 - How to compile
4 - Directory tree
5 - Contact information



1 - What is this?
-----------------

GTSTAT is a small tool to read the file 'GUN-TACTYX-results.txt', filter out 
certain matches and output the remaining matches, in both GUN-TACTYX format 
and human readable format, to another file.

For example, you can use it to filter out all matches in which your team 
plays, all matches playing in a certain level, etc.



2 - Usage
---------

Type 'gtstat /h' in a console to view usage information.

(If you don't know how, you can click on Start -> Run then type "command". 
Under Windows 2000 and XP, you should type "cmd" instead.)



3 - How to compile
------------------

If you're using an IDE (Integrated Development Environment), create a new 
project and add all source (src/*.cpp) and header (src/*.h) files to it. 
Compile and everything should work fine. (if not, drop me an e-mail with a 
description of the problem (a solution would be even better ;-) )

If you're using MinGW32, type in a console:
(assumes you've unzipped GTSTAT to c:\GUN-TACTYX)

cd c:\GUN-TACTYX
g++ src/*.cpp -O3 -o gtstat.exe -s



4 - Directory tree
------------------

/               - GTSTAT root directory
src/            - Source code and header files (*.cpp and *.h)



5 - Contact information
-----------------------

You may contact me in the following manners:

* Send E-mail to:

    tobi_v@users.sourceforge.net
    tobivollebregt@hotmail.com
