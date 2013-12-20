
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
-- $Id: tc639.vhd,v 1.3 2001-10-29 02:12:45 paw Exp $
-- $Revision: 1.3 $
--
-- ---------------------------------------------------------------------


--                 ****************************               --
-- Ported to VHDL 93 by port93.pl - Tue Nov  5 16:37:51 1996  --
--                 ****************************               --



--                 ****************************                   --
-- Reversed to VHDL 87 by reverse87.pl - Tue Nov  5 11:26:14 1996  --
--                 ****************************                    --



--                 ****************************               --
-- Ported to VHDL 93 by port93.pl - Mon Nov  4 17:36:28 1996  --
--                 ****************************               --



ENTITY c03s04b01x00p01n01i00639ent IS
END c03s04b01x00p01n01i00639ent;

ARCHITECTURE c03s04b01x00p01n01i00639arch OF c03s04b01x00p01n01i00639ent IS

  type            four_value    is ('Z','0','1','X');
  subtype         binary          is four_value range '0' to '1';
  subtype      word       is bit_vector(0 to 15);
  constant   size      : integer := 7;
  type       primary_memory  is array(0 to size) of word;

  type    primary_memory_module is
    record
      enable          : binary;
      memory_number   : primary_memory;
    end record;

  type       primary_memory_module_file     is file of primary_memory_module;

  constant C38 : word          := (others => '1');
  constant C44 : primary_memory       := (others => C38);
  constant C45 : primary_memory_module    := ('1',C44);

  signal       k    : integer := 0;

BEGIN
  TESTING: PROCESS
    file filein    : primary_memory_module_file open read_mode is "iofile.43";
    variable  v    : primary_memory_module;
  BEGIN
    for i in 1 to 100 loop
      assert(endfile(filein) = false) report"end of file reached before expected";
      read(filein,v);
      if (v /= C45) then
        k <= 1;
      end if;
    end loop;
    wait for 1 ns;
    assert NOT(k = 0)
      report "***PASSED TEST: c03s04b01x00p01n01i00639"
      severity NOTE;
    assert (k = 0)
      report "***FAILED TEST: c03s04b01x00p01n01i00639 - File reading operation (primary_memory_module file type) failed."
      severity ERROR;
    wait;
  END PROCESS TESTING;

END c03s04b01x00p01n01i00639arch;
