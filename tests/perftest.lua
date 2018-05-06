--
-- PERFTEST.LUA         Copyright (c) 2007-08, Asko Kauppi <akauppi@gmail.com>
--
-- Performance comparison of multithreaded Lua (= how much ballast does using
-- Lua Lanes introduce)
--
-- Usage:
--      [time] lua -lstrict perftest.lua [threads] [-plain|-single[=2..n]] [-time] [-prio[=-2..+2[,-2..+2]]]
--
--      threads: number of threads to launch (loops in 'plain' mode)
--      -plain: runs in nonthreaded mode, to get a comparison baseline
--      -single: runs using just a single CPU core (or 'n' cores if given)
--      -prio: sets odd numbered threads to higher/lower priority
--
-- History:
--      AKa 20-Jul-08: updated to Lanes 2008
--      AK 14-Apr-07: works on Win32
--
-- To do:
--      (none?)
--

-- On MSYS, stderr is buffered. In this test it matters.
-- Seems, even with this MSYS wants to buffer linewise, needing '\n'
-- before actual output.
--
local MSYS= os.getenv("OSTYPE")=="msys"


local lanes = require "lanes".configure{ with_timers = false}

local m= require "argtable"
local argtable= assert( m.argtable )

local N= 1000   -- threads/loops to use
local M= 1000   -- sieves from 1..M
local PLAIN= false      -- single threaded (true) or using Lanes (false)
local SINGLE= 0     -- cores to use (0 / 1..n) 
local TIME= false       -- use Lua for the timing
local PRIO_ODD, PRIO_EVEN   -- -3..+3

local function HELP()
    io.stderr:write( "Usage: lua perftest.lua [threads]\n" )
end

-- nil -> +2
-- odd_prio[,even_prio]
--
local function prio_param(v)
    if v==true then return 2,-2 end

    local a,b= string.match( v, "^([%+%-]?%d+)%,([%+%-]?%d+)$" )
    if a then
        return tonumber(a), tonumber(b)
    elseif tonumber(v) then
        return tonumber(v)
    else
        error( "Bad priority: "..v )
    end
end

for k,v in pairs( argtable(...) ) do
    if k==1 then            N= tonumber(v) or HELP()
    elseif k=="plain" then  PLAIN= true
    elseif k=="single" then  SINGLE= v  -- number
    elseif k=="time" then   TIME= true
    elseif k=="prio" then   PRIO_ODD, PRIO_EVEN= prio_param(v)
    else                    HELP()
    end
end

PRIO_ODD= PRIO_ODD or 0
PRIO_EVEN= PRIO_EVEN or 0


-- SAMPLE ADOPTED FROM Lua 5.1.1 test/sieve.lua --

-- the sieve of of Eratosthenes programmed with coroutines
-- typical usage: lua -e N=1000 sieve.lua | column

-- AK: Wrapped within a surrounding function, so we can pass it to Lanes
--     Note that coroutines can perfectly fine be used within each Lane. :)
--
-- AKa 20-Jul-2008: Now the wrapping to one function is no longer needed;
--     Lanes 2008 can take the used functions as upvalues.
--
local function sieve_lane(N,id)

 if MSYS then
   io.stderr:setvbuf "no"
 end

 -- generate all the numbers from 2 to n
 local function gen (n)
  return coroutine.wrap(function ()
    for i=2,n do coroutine.yield(i) end
  end)
 end

 -- filter the numbers generated by `g', removing multiples of `p'
 local function filter (p, g)
  return coroutine.wrap(function ()
    while 1 do
      local n = g()
      if n == nil then return end
      if math.fmod(n, p) ~= 0 then coroutine.yield(n) end
    end
  end)
 end

 local ret= {}      -- returned values: { 2, 3, 5, 7, 11, ... }
 N=N or 1000	    -- from caller
 local x = gen(N)   -- generate primes up to N
 while 1 do
  local n = x()		-- pick a number until done
  if n == nil then break end
  --print(n)		-- must be a prime number
  table.insert( ret, n )

  x = filter(n, x)	-- now remove its multiples
 end
 
 io.stderr:write(id..(MSYS and "\n" or "\t"))   -- mark we're ready

 return ret     
end
-- ** END OF LANE ** --


-- Keep preparation code outside of the performance test
--
local f_even= lanes.gen( "base,coroutine,math,table,io",  -- "*" = all
                            { priority= PRIO_EVEN }, sieve_lane )
                             
local f_odd= lanes.gen( "base,coroutine,math,table,io",  -- "*" = all
                            { priority= PRIO_ODD }, sieve_lane )

io.stderr:write( "*** Counting primes 1.."..M.." "..N.." times ***\n\n" )

local t0= TIME and lanes.now_secs()

if PLAIN then
    io.stderr:write( "Plain (no multithreading):\n" )

    for i=1,N do
        local tmp= sieve_lane(M,i)
        assert( type(tmp)=="table" and tmp[1]==2 and tmp[168]==997 )
    end
else
    if SINGLE > 0 then
        io.stderr:write( (tonumber(SINGLE) and SINGLE or 1) .. " core(s):\n" )
        lanes.set_singlethreaded(SINGLE)    -- limit to N cores (just OS X)
    else
        io.stderr:write( "Multi core:\n" )
    end

    if PRIO_ODD ~= PRIO_EVEN then
        io.stderr:write( ( PRIO_ODD > PRIO_EVEN and "ODD" or "EVEN" )..
                        " LANES should come first (odd:"..PRIO_ODD..", even:"..PRIO_EVEN..")\n\n" )
    else
        io.stderr:write( "EVEN AND ODD lanes should be mingled (both: "..PRIO_ODD..")\n\n" )
    end
    local t= {}
    for i=1,N do
        t[i]= ((i%2==0) and f_even or f_odd) (M,i)
    end

    -- Make sure all lanes finished
    --
    for i=1,N do
        local tmp= t[i]:join()
        assert( type(tmp)=="table" and tmp[1]==2 and tmp[168]==997 )
    end
end

io.stderr:write "\n"

if TIME then
    local t= lanes.now_secs() - t0
    io.stderr:write( "*** TIMING: "..t.." seconds ***\n" )
end

--
-- end
