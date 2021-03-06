
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
-- $Id: tc403.vhd,v 1.2 2001-10-26 16:29:53 paw Exp $
-- $Revision: 1.2 $
--
-- ---------------------------------------------------------------------

ENTITY c03s02b01x01p18n01i00403ent IS
END c03s02b01x01p18n01i00403ent;

ARCHITECTURE c03s02b01x01p18n01i00403arch OF c03s02b01x01p18n01i00403ent IS
  type MEM is array (positive range <>) of BIT;
  type ME1 is array (natural range <>) of Integer;
  subtype ME2 is ME1(0 to 3);
  subtype M1 is MEM (1 to 5) ;
  function WR_OR(Input : ME1) return M1 is
  begin
    for I in Input'Range loop
      if Input(I) = 20 then
        return "11111" ;
      end if;
    end loop;
  end WR_OR;
  procedure F2 (X1 : in MEM) is
  begin
    assert NOT(X1="11111")
      report "***PASSED TEST: c03s02b01x01p18n01i00403"
      severity NOTE;
    assert (X1="11111")
      report "***FAILED TEST: c03s02b01x01p18n01i00403 - "
      severity ERROR;
  end F2;
BEGIN
  TESTING: PROCESS
    variable V1 :ME2  := (10, 20, 30, 40);
  BEGIN
    F2(WR_OR(V1)) ;  -- No_failure_here
    wait;
  END PROCESS TESTING;

END c03s02b01x01p18n01i00403arch;
