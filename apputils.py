# 
# apputils.py
#
# Purpose: Contain various utility functions that are used locally by the application.
#
import os
import sys
import tempfile
import mmap
import numpy as np
from mpi4py import MPI
import scipy.sparse as sparse


epsilon = np.float(10.0**(-15))
MAX_NUMPY_ARRAY_BYTES=1000000000
MMAP_DIR="~/temp"
NumPy2MPIType={'float32':MPI.FLOAT, 
               'int32':MPI.INT, 
               'complex64':MPI.COMPLEX, 
               'int64':MPI.LONG}

def set_mmap_dir(mmapDir="~/temp"):
   global MMAP_DIR

   MMAP_DIR = mmapDir
# end set_mmap_dir()

def create_NUMPY_memmap(shape=(1,), dtype=np.int32, mode='w+', mapDir=None):
   global MMAP_DIR

   if mapDir is None:
      mapDir = MMAP_DIR
   # endif
   (tempFD, tempFilepath) = tempfile.mkstemp(prefix='tmp', suffix='.dtmp', dir=mapDir)
   memmapArr = np.memmap(filename=tempFilepath, shape=shape, dtype=dtype, mode=mode)

   return memmapArr
# end create_NUMPY_memmap()

def __MPIBcast_NUMPY_Array(inArray, root=0):
   global MMAP_DIR
   global MAX_NUMPY_ARRAY_BYTES
   global NumPy2MPIType

   MPIComm = MPI.COMM_WORLD
   procRank = MPIComm.Get_rank()
   numProcs = MPIComm.Get_size()

   outArray = inArray
   numElems = None
   dtype = None

   if procRank == root:
      if inArray is not None:
         if isinstance(inArray, np.ndarray) or isinstance(inArray, np.memmap):
            numElems = np.int64(len(inArray))
            dtype = inArray.dtype
         else:
            raise TypeError('Input argument is not type numpy.ndarray or numpy.memmap') 
         # endif
      else:
         raise TypeError('Input argument \'None\'is not type numpy.ndarray or numpy.memmap') 
      # endif
   # endif
   numElems = MPIComm.bcast(numElems, root=root)
   dtype = MPIComm.bcast(dtype, root=root)

   numBytes = numElems*np.dtype(dtype).itemsize
   if numBytes < MAX_NUMPY_ARRAY_BYTES:
      outArray = MPIComm.bcast(outArray, root=root)
   else:
      if procRank != root:
         outArray = create_NUMPY_memmap(shape=(numElems,), dtype=dtype, mode='w+')
      # endif
      
      MPIComm.Bcast([outArray, numElems, NumPy2MPIType[dtype.name]], root=root)
   # endif

   return outArray
# end __MPIBcast_NUMPY_Array()

def __MPIBcast_SCIPY_CSR_Matrix(inMatrix, root=0):
   MPIComm = MPI.COMM_WORLD
   procRank = MPIComm.Get_rank()

   outMatrix = inMatrix

   # Break apart the CSR sparse matrix and broadcast its components.
   data = None
   indptr = None
   indices = None
   shape = None
   dtype = None
   if procRank == root:
      if inMatrix is not None:
         data = inMatrix.data
         indptr = inMatrix.indptr
         indices = inMatrix.indices
         shape = inMatrix.shape
         dtype = inMatrix.dtype
      else:
         raise TypeError('Input argument \'None\' is not of type scipy.sparse.csr_matrix') 
      # endif
   # endif
   #data = MPIComm.bcast(data, root=root)
   #indptr = MPIComm.bcast(indptr, root=root)
   #indices = MPIComm.bcast(indices, root=root)
   data = __MPIBcast_NUMPY_Array(data, root=root)
   indptr = __MPIBcast_NUMPY_Array(indptr, root=root)
   indices = __MPIBcast_NUMPY_Array(indices, root=root)
   shape = MPIComm.bcast(shape, root=root)
   dtype = MPIComm.bcast(dtype, root=root)

   # Reconstruct the sparse matrix from its components.

   if procRank != root:
      outMatrix = sparse.csr_matrix(shape, dtype=dtype)
      outMatrix.data = data
      outMatrix.indptr = indptr
      outMatrix.indices = indices
   # endif

   return outMatrix
# end __MPIBcast_SCIPY_CSR_Matrix()

def MPIBcast_SCIPY_Sparse_Matrix(inMatrix, root=0):
   retMatrix = None

   if inMatrix is None or isinstance(inMatrix, sparse.csr_matrix):
      retMatrix = __MPIBcast_SCIPY_CSR_Matrix(inMatrix, root=root) 
   else:
      raise TypeError('Input argument is not a recognized or handled SciPy sparse matrix type.')
   # endif
   MPI.COMM_WORLD.Barrier()
   
   return retMatrix
# end MPIBcast_SCIPY_Sparse_Matrix()


def MPIAbort(code=0):
   MPI.COMM_WORLD.Abort(code)
# end MPIAbort()

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
   procMessage("{msg}".format(msg=msg), root=root, msg_type='DEBUG')
# end DEBUG_MSG()
def ERROR_MSG(msg, root=-1):
   procMessage("{msg}".format(msg=msg), root=root, msg_type='ERROR')
# end ERROR_MSG()
def WARNING_MSG(msg, root=-1):
   procMessage("{msg}".format(msg=msg), root=root, msg_type='WARNING')
# end WARNING_MSG()
#

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
# end clipValue()

def forceIntValue(inValue, lower, upper):
   return clipValue(inValue, lower, upper, valueType=int)
# end forceIntValue()

def forceIntValueOdd(inValue, lower, upper, align=0):
   # Set how to align the resulting odd number relative to the original value:
   #  align = 0 => find greatest odd number <= inValue.
   #  align = 1 => find least odd number >= inValue.
   if align > 0:
      align = 1
   else:
      align = 0
   # endif
   
   newValue = 2*(int(0.5*clipValue(inValue, lower, upper, valueType=int))) + (2*align - 1)

   # Adjust the final value to be within the clip range.  This may actually violate the specified
   # alignment.
   if newValue < lower:
      newValue += 2
   # endif
   if newValue > upper:
      newValue -= 2
   # endif

   return newValue
# end forceIntValueOdd()

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
   diff = (a - a.mean())
   stddev = a.std()
   mask = np.logical_and(diff == 0.0. stddev == 0.0)
   result = np.divide(diff, stddev, where=np.logical_not(mask))
   result[mask] = 0.0
   return result
# end snr()
#

def scaleDelays(freqs, topFreq=None):
   """
   Calculate the scaled relative delays of the given collection of frequencies from the maximum
   frequency in the collection, if topFreq is not specified.  In the case that topFreq is specified,
   then the delays are relative to that frequency.  The frequencies are assumed to be in units of MHz.
   """
   # Dispersion constant in MHz^2 s / pc cm^-3
   dispConst = 4.148808e3
   # Compute inverse square of each of the frequencies and the inverse square of the maximum frequency
   # among them.
   sqrInvFreqs = 1.0/(freqs**2)
   if topFreq is None:
      sqrInvFreqN = 1.0/(freqs.max()**2)
   else:
      sqrInvFreqN = 1.0/topFreq**2
   # endif

   # Compute the relative delays from the maximum frequency.
   return dispConst*(sqrInvFreqs - sqrInvFreqN)
# end scaleDelays()

def computeFreqs(centerFreq, bandwidth, botIndex=None, topIndex=None, numBins = None):
   """
   Compute the collection of frequencies for the bandpass region defined by a center frequency, total
   bandwidth, a bottom frequency index, a top frequency index, and total number of bins that the total
   bandwidth is divided amongst (if total bins is not given, it is assumed that topIndex + 1 is the
   total number of bins.
   """

   freqs = None
   if topIndex is not None or numBins is not None:
      if numBins is None:
         numBins = topIndex + 1
      elif topIndex is None:
         topIndex = numBins - 1
      else:
         topIndex = np.minimum(topIndex, numBins - 1)
      # endif

      if botIndex is None:
         botIndex = 0
      # endif

      numFreqs = topIndex - botIndex + 1
      indices = np.arange(numFreqs)
      freqs = np.zeros(numFreqs, dtype=np.float32)

      BWFactor = bandwidth/(2.0*numBins)
      for index in indices:
         freqIndex = botIndex + index
         freqs[index] = centerFreq + BWFactor*(2.0*freqIndex - numBins)
      # endfor
   # endif
   
   return freqs
# end computeFreqs()
