# 
# apputils.py
#
# Purpose: Contain various utility functions that are used locally by the application.
#
import os
import sys
import numpy as np
from mpi4py import MPI



def procMessage(msg, root=-1, msg_type=None):
   if msg_type is not None:
      msg_type = " ({type})".format(type=msg_type)
   else:
      msg_type =""
   # endif
      
   if root == -1 or root == MPI.COMM_WORLD.Get_rank():
      print 'From process {rank}{type} => {msg}'.format(rank=MPI.COMM_WORLD.Get_rank(), msg=msg, 
                                                         type=msg_type)
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
      return np.array([arry[i::ndown][0:n_rep] for i in range(ndown)]).mean(0)
   else:
      return arry
# end Decimate()

def DecimateNPY(arry, ndown=2):
   """
   Takes an n-dimesional array and decimates it over the first dimension by a factor of ndown.  This 
   is an optimization of the original Decimate algorithm in that it takes advantage of the Numpy API
   to drastically speedup the decimation process.
   """
   if ndown > 1:
      n_rep = int( len(arry)/ndown )
      if len(arry.shape) > 1:
         shape = (n_rep, ndown) + arry.shape[1:]
      else:
         shape = (n_rep, ndown)
      # endif
      temp = np.ndarray(buffer=arry, dtype=arry.dtype, shape=shape)
      return temp.mean(1)
   else:
      return arry
   # endif
# end DecimateNPY()

def createWaterfallFilepath(tile=0, tuning=0, beam=0, label=None, workDir=None):
   fileLabel = ""
   fileDir = "."
   if label is not None:
      fileLabel = "_{label}".format(label=label)
   # endif
   if workDir is not None:
      fileDir = workDir
   # endif

   return "{dir}/waterfall{label}-S{tile}-B{beam}T{tune}.npy".format(dir=fileDir, label=fileLabel,
                                                                     tile=tile, beam=beam,
                                                                     tune=tuning)
# end createWaterfallFilepath()

def parseWaterfallFilepath(filepath=None):
   if filepath == None:
      return (None, None, None)
   # endif
 
   filename = os.path.basename(filepath)
   fields = filename.split('-')
   # Extract the tile index.
   index = int(fields[1][1:])
   # Extract the beam and tuning numbers.
   beamTunePart = fields[2].split('.')[0].split('T')
   beam = int(beamTunePart[0][1:])
   tune = int(beamTunePart[1])

   return (beam, tune, index)
# end parserWaterfallFilepath()

# Sort waterfall filepaths according the tile index in the file path.
def sortWaterfallFilepaths(filepaths=None):
   if filepaths == None:
      return None
   # endif

   filemapping = dict()
   indices = np.zeros(len(filepaths))
   i = 0
   for filepath in filepaths:
      (beam, tune, index) = parseWaterfallFilepath(filepath)
      indices[i] = index
      filemapping[index] = filepath
      i = i + 1
   # endfor
   indices.sort()

   return [filemapping[i] for i in indices]
# end sortWaterfallFilepaths()

def savitzky_golay(y, window_size, order, deriv=0):
   """Smooth (and optionally differentiate) data with a Savitzky-Golay filter

   This implementation is based on [1]_.

   The Savitzky-Golay filter removes high frequency noise from data.
   It has the advantage of preserving the original shape and
   features of the signal better than other types of filtering
   approaches, such as moving averages techhniques.

   Parameters
   ----------
   y : array_like, shape (N,)
       the values of the time history of the signal.
   window_size : int
       the length of the window. Must be an odd integer number.
   order : int
       the order of the polynomial used in the filtering.
       Must be less then `window_size` - 1.
   deriv: int
       the order of the derivative to compute
       (default = 0 means only smoothing)

   Returns
   -------
   y_smooth : ndarray, shape (N)
       the smoothed signal (or it's n-th derivative).

   Notes
   -----
   The Savitzky-Golay is a type of low-pass filter, particularly
   suited for smoothing noisy data. The main idea behind this
   approach is to make for each point a least-square fit with a
   polynomial of high order over a odd-sized window centered at
   the point.

   Examples
   --------
   >>> t = np.linspace(-4, 4, 500)
   >>> y = np.exp(-t ** 2)
   >>> np.random.seed(0)
   >>> y_noisy = y + np.random.normal(0, 0.05, t.shape)
   >>> y_smooth = savitzky_golay(y, window_size=31, order=4)
   >>> print np.rms(y_noisy - y)
   >>> print np.rms(y_smooth - y)

   References
   ----------
   .. [1] http://www.scipy.org/Cookbook/SavitzkyGolay
   .. [2] A. Savitzky, M. J. E. Golay, Smoothing and Differentiation of
      Data by Simplified Least Squares Procedures. Analytical
      Chemistry, 1964, 36 (8), pp 1627-1639.
   .. [3] Numerical Recipes 3rd Edition: The Art of Scientific Computing
      W.H. Press, S.A. Teukolsky, W.T. Vetterling, B.P. Flannery
      Cambridge University Press ISBN-13: 9780521880688
   """
   try:
       window_size = np.abs(np.int(window_size))
       order = np.abs(np.int(order))
   except ValueError, msg:
       raise ValueError("window_size and order have to be of type int")

   if window_size % 2 != 1 or window_size < 1:
       raise TypeError("window_size size must be a positive odd number")

   if window_size < order + 2:
       raise TypeError("window_size is too small for the polynomials order")

   order_range = range(order + 1)

   half_window = (window_size - 1) // 2

   # precompute coefficients
   b = np.mat([[k ** i for i in order_range]
               for k in range(-half_window, half_window + 1)])
   m = np.linalg.pinv(b).A[deriv]

   # pad the signal at the extremes with
   # values taken from the signal itself
   firstvals = y[0] - np.abs(y[1:half_window + 1][::-1] - y[0])
   lastvals = y[-1] + np.abs(y[-half_window - 1:-1][::-1] - y[-1])

   y = np.concatenate((firstvals, y, lastvals))

   return np.convolve(y, m, mode='valid')
# end savitzky_golay()

def RFI(sp,std):
   # Correct bandpass RFI.
   bandpass = sp.mean(0)
   noiseFloor = np.median(sp)
   bandpassMask = np.where( np.abs(bandpass - np.median(bandpass)) > std/np.sqrt(sp.shape[0]) )
   sp[:, bandpassMask] = noiseFloor

   # Correct baseline RFI.
   baseline = sp.mean(1)
   noiseFloor = np.median(sp)
   baselineMask = np.where( np.abs(baseline - np.median(baseline)) > std/np.sqrt(sp.shape[1]) )
   sp[baselineMask, :] = noiseFloor

   return sp
# end RFI()

def snr(a):
   # Numpy std function computes the standard deviation from the theoretical variance, not the proper
   # sample variance since the mean is being derived from the data. However, for an extremely large
   # number of data points, the two are not substantially different.
   return (a - a.mean() )/a.std()
# end snr()
#

def scaleDelays(freqs):
   """
   Calculate the scaled relative delays of the given collection of frequencies from the maximum
   frequency in the collection.  The frequencies are assumed to be in units of MHz.
   """
   # Dispersion constant in MHz^2 s / pc cm^-3
   dispConst = 4.148808e3
   # Compute inverse square of each of the frequencies and the inverse square of the maximum frequency
   # among them.
   sqrInvFreqs = 1.0/(freqs**2)
   sqrInvFreqN = 1.0/(freqs.max()**2)

   # Compute the relative delays from the maximum frequency.
   return dispConst*(sqrInvFreqs - sqrInvFreqN)
# end scaleDelays()

def computeFreqs(centerFreq, bandwidth, botIndex, topIndex, numBins = None):
   """
   Compute the collection of frequencies for the bandpass region defined by a center frequency, total
   bandwidth, a bottom frequency index, a top frequency index, and total number of bins that the total
   bandwidth is divided amongst (if total bins is not given, it is assumed that topIndex + 1 is the
   total number of bins.
   """
   if numBins is None:
      numBins = topIndex + 1
   # endif

   numFreqs = topIndex - botIndex + 1
   indices = np.arange(numFreqs)
   freqs = np.zeros(numFreqs, dtype=np.float32)

   BWFactor = bandwidth/(2.0*numBins)
   for index in indices:
      freqIndex = botIndex + index
      freqs[index] = centerFreq + BWFactor*(2*freqIndex - numBins)
   # endfor
# end computeFreqs()
