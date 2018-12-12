# 
# apputils.py
#
# Purpose: Contain various utility functions that are used locally by the application.
#
import os
import sys
import numpy
from mpi4py import MPI



def procMessage(msg, root=-1):
   if root == -1 or root == MPI.COMM_WORLD.Get_rank():
      print 'From process {rank}=> {msg}'.format(rank=MPI.COMM_WORLD.Get_rank(), msg=msg)
   # endif
# end procMessage()

def DEBUG_MSG(msg, root=-1):
   procMessage("DEBUG: {msg}".format(msg=msg), root)
# end debugMsg()

def clipValue(inValue, lower, upper, valueType=None):
   # CCY - NOTE: while this works, it needs to be smarter about checking that the type specified is a
   # numerical type that is not complex and that lower and upper do not exceed the min/max bounds for
   # that type.
   #
   if valueType is None:
      valueType = int
   # endif
   
   # Return inValue to be in the range from <lower> to <upper> with the specified type.
   result = max([lower, inValue])
   result = min([upper, result])
   result = valueType(result)
   return result
# end clipVale()

def forceIntValue(inValue, lower, upper):
   return clipValue(inValue, lower, upper, valueType=int)
# end forceIntVale()

def Decimate(arry, ndown=2):
   """
   Takes a N dimensional array and decimates it by a factor of ndown, default = 2, along axis = 0
   Code adapted from analysis.binarray module: 
   http://www.astro.ucla.edu/~ianc/python/_modules/analysis.html#binarray 
   from Ian's Python Code (http://www.astro.ucla.edu/~ianc/python/index.html)
    
   Optimized for time series' with length = multiple of 2.  Will handle others, though.

   Required:
    
   ts  -  input time series

   Options:
    
   ndown  -  Factor by which to decimate time series. Default = 2.
   if ndown <= 1, returns ts       
   """
   #return a decimated array shape = x, y, z, ...) with shape =  x/ndown, y, z, ....

   if ndown > 1:
      n_rep = int(len(arry) / ndown)
      return numpy.array([arry[i::ndown][0:n_rep] for i in range(ndown)]).mean(0)
   else:
      return arry
# end Decimate()
