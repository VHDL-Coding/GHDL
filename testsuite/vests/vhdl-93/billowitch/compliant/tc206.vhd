
-- Copyright (C) 2001 Bill Billowitch.

-- Some of the work to develop this test suite was done with Air Force
-- support.  The Air Force and Bill Billowitch assume no
-- responsibilities for this software.

-- This file is part of VESTs (Vhdl tESTs).

-- VESTs is free software; you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the
-- Free Software Foundation; either version 2 of the License, or (at
-- your option) any later version. 

-- VESTs is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
-- for more details. 

-- You should have received a copy of the GNU General Public License
-- along with VESTs; if not, write to the Free Software Foundation,
-- Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA 

-- ---------------------------------------------------------------------
--
-- $Id: tc206.vhd,v 1.2 2001-10-26 16:29:45 paw Exp $
-- $Revision: 1.2 $
--
-- ---------------------------------------------------------------------

ENTITY c03s01b00x00p08n01i00206ent IS
  type i is range 3 downto 1;
END c03s01b00x00p08n01i00206ent;

ARCHITECTURE c03s01b00x00p08n01i00206arch OF c03s01b00x00p08n01i00206ent IS
  constant r:i:=2;
BEGIN
  TESTING: PROCESS
    variable m:i;
  BEGIN
    m := i'leftof(r);
    assert NOT( m=3 ) 
      report "***PASSED TEST: c03s01b00x00p08n01i00206"
      severity NOTE;
    assert ( m=3 ) 
      report "***FAILED TEST: c03s01b00x00p08n01i00206 - Left of the value testing failed." 
      severity ERROR;
    wait;
  END PROCESS TESTING;

END c03s01b00x00p08n01i00206arch;
