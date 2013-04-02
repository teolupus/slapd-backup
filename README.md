slapd-backup
============

OpenLDAP (slapd) backup and restore routines

This script is provided as an example on how to backup OpenLDAP (slapd)
version 2.4 running on Ubuntu Server 12 LTS. While it should work on other
distributions, you may need to adjust the location of some files.

Error codes:
  0) Backup successful.
  1) Fatal errors occurred during the process. Backup not generated.
  2) One or more non-fatal errors occurred during the process. Backup may be
     corrupted or incomplete.
  3) Backup aborted or interrupted.

To do (known limitations):
  * A restore script that receives the backup archive file as an input and
    does the right job would be handy. Coming soon...

Licensing information
---------------------
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
ou should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
