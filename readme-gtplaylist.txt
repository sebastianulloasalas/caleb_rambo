/*  GTPLAYLIST - Generates a match playlist for the use with GUN-TACTYX
 *  Copyright (C) 2004  Frank Plohmann
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
 *  Frank Plohmann
 *  guntactyx@franks-planet.de
 */



                    September 28th 2004
INDEX

1 - What is this?
2 - Usage
3 - How to compile
4 - Directory tree
5 - Contact information
6 - Version history



1 - What is this?
-----------------

GTPLAYLIST is made for generating match playlists which can be used with the
programming game "GUN-TACTYX" developed by Leonardo Boselli.

It looks into a given directory for compiled bot files (.amx) and writes
a playlist file. It is possible to modify the way the playlist is made in
several ways.

GTPLAYLIST is written in C# so it needs a .NET runtime environment to work. Beside
the Microsoft .NET runtime framework 1.1 it should also run using Mono or DotGNU.

http://www.microsoft.com/net/
http://www.mono-project.com
http://www.dotgnu.org/



2 - Usage
---------

Type 'gtplaylist /h' in a console to view usage information.

(If you don't know how, you can click on Start -> Run then type "command". 
Under Windows 2000 and XP, you should type "cmd" instead.)



3 - How to compile
------------------

The best way to modify and/or compile GTPLAYLIST is to use "SharpDevelop".
It is a free .NET IDE for developing .NET programs in C# or VB.NET. The
original MS .NET runtime and SDK (also free) is needed to run "SharpDevelop".

After installing the MS .NET SDK and "SharpDeveolp" you can open the project 
by using the file "GTPlaylist.cmbx".

http://www.microsoft.com/net/
http://www.icsharpcode.net/OpenSource/SD/



4 - Directory tree
------------------

/               - GTPLAYLIST root directory
src/            - Source code and combine/project file



5 - Contact information
-----------------------

You may contact me in the following manners:

* Send E-mail to:

    guntactyx@franks-planet.de



6 - Version history
-------------------

1.00 (2004-09-13)
- initial release

1.01 & 1.02 (-)
- inofficial bugfix releases

1.03 (2004-09-22)
- added "/rbl" to randomize the bot list
- added "/rcem" to randomize corners in each match

1.04 (2004-09-26)
- added "/rbem" to randomize bots order in each match

1.05 (2004-09-29)
- first official release with source code
- added "/ftbf" to force given list of bots are used first
- added "/mm" to be able to set a maximum number of matches are
  generated (this is far from beeing perfect ;) )
