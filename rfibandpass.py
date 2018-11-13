import os
import sys
import numpy as np
from  mpi4py import MPI
import ConfigParser
import mmap
from optparse import OptionParser
from apputils import procMessage, forceIntValue, clipValue

SGKernels = None # Dictionary of kernels to use in the Savitsky-Golay smoothing.

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

   global SGKernels

   try:
      window_size = np.abs(np.int(window_size))
      order = np.abs(np.int(order))
   except ValueError, msg:
      raise ValueError("window_size and order have to be of type int")
   # endtry

   if window_size % 2 != 1 or window_size < 1:
      #raise TypeError("window_size size must be a positive odd number")
      window_size += 1
   # endif

   if window_size < order + 2:
      raise TypeError("window_size is too small for the polynomials order")
   # endif

   half_window = (window_size - 1) // 2

   if (window_size, order, deriv) not in SGKernels:
      order_range = range(order + 1)
      # precompute coefficients
      b = np.mat([[k ** i for i in order_range] for k in range(-half_window, half_window + 1)])
      m = np.linalg.pinv(b).A[deriv]
      SGKernels[window_size, order, deriv] = m
   else:
      m = SGKernels[window_size, order, deriv]
   # endif

   # pad the signal at the extremes with
   # values taken from the signal itself
   firstvals = y[0] - np.abs(y[1:half_window + 1][::-1] - y[0])
   lastvals = y[-1] + np.abs(y[-half_window - 1:-1][::-1] - y[-1])

   y = np.concatenate((firstvals, y, lastvals))

   return np.convolve(y, m, mode='valid')

def snr(x):
   return (x-x.mean())/x.std()
# end snr()

def bpf(x, windows = 40):
   mask = np.nonzero(snr(x / savitzky_golay(x, windows, 1)) > 1)[0]
   mask2= np.zeros(x.shape[0])
   mask2[mask] = 1.
   y = np.ma.array(x, mask = mask2)
   s = np.arange(len(y))
   fit = np.ma.polyfit(s, y, 4)
   bp = x
   bp[mask] = np.poly1d(fit)(s)[mask]
   return savitzky_golay(bp, windows, 2)
# end bpf()


def RFImask(spr):#sp has shape[:,:]
    sprMean1 = spr.mean(1)
    sprMean1.sort()
    sprMean0 = spr.mean(0)
    sprMean0.sort()
    sprMedian1 = sprMean1[sprMean1.shape[0]/2]
    sprMedian0 = sprMean0[sprMean0.shape[0]/2]
    x = np.nonzero( np.fabs(sprMean1) > (2*sprMedian1 - sprMean1[1]) )[0]
    y = np.nonzero( np.fabs(sprMean0) > (2*sprMedian0 - sprMean0[1]) )[0]
    return (x, y)

def massagesp(spectrometer, windows_x=43, windows_y=100):
   bp = bpf(spectrometer.mean(0), windows_x)
   spectrometer /= bp
   bl = bpf(spectrometer.mean(1), windows_y)
   spectrometer = (spectrometer.T - bl).T
   rfiIndices  = RFImask(spectrometer)
   mask = np.zeros((spectrometer.shape))
   mask[rfiIndices[0],:] = 1.
   mask[:, rfiIndices[1]] = 1.
   mean = np.ma.array(spectrometer, mask = mask ).mean()
   spectrometer[rfiIndices[0],:] = mean
   spectrometer[:, rfiIndices[1]] = mean
   spectrometer -= mean
   return spectrometer
# end massagesp()


# main routine
#
def main_routine(args):
   global SGKernels
   SGKernels = dict()

   comm = MPI.COMM_WORLD
   rank = comm.Get_rank()
   nProcs = comm.Get_size()

   # Setup and parse commandline.
   usage = "USAGE: %prog [options] <waterfall files>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option('-l', '--lower-cutoff', dest='fftLower', type='int', default=0,
                           help='Lower FFT index (between 0 and 4095) for bandpass filtering.', 
                           metavar='INDEX')
   cmdlnParser.add_option('-u', '--upper-cutoff', dest='fftUpper', type='int', default=4095,
                           help='Upper FFT index (between 0 and 4095) for bandpass filtering.', 
                           metavar='INDEX')
   cmdlnParser.add_option('-w', '--work-dir', dest='workDir', type='string', default='.',
                           help='Path to the working directory.', metavar='PATH')
   cmdlnParser.add_option('-p', '--outfile-prefix', dest='outPrefix', type='string', default='rfibp',
                           help='Prefix to attach to the output filtered spectrogram files.',
                           metavar='PREFIX')
   cmdlnParser.add_option('-bp', '--bandpass-window', dest='bpWindow', type='int', default=10,
                           help='Bandpass smoothing window size.', metavar='INT')
   cmdlnParser.add_option('-bl', '--baseline-window', dest='blWindow', type='int', default=50,
                           help='Baseline smoothing window size.', metavar='INT')
   (cmdlnOpts, waterfallFiles) = cmdlnParser.parse_args(args)

   fftLower = forceIntValue(cmdlnOpts.fftLower, 0, 4095)
   fftUpper = forceIntValue(cmdlnOpts.fftUpper, 0, 4095)
   bpWindow = forceIntValue(cmdlnOpts.bpWindow, 1, 9999)
   blWindow = forceIntValue(cmdlnOpts.blWindow, 1, 9999)

   if fftUpper <= fftLower:
      print 'ERROR: rfibandpass.py -> Upper FFT cutoff must be greater than lower FFT cutoff'
      sys.exit(1)
   # endif

   numFiles = len(waterfallFiles)
   if numFiles > 0:
      waterfallFiles.sort()

      # Determine which files the current process will filter.
      filesPerProc = int(numFiles/nProcs)
      fileIndices = np.arange(filesPerProc) + filesPerProc*rank
      if rank == 0:
         remainder = np.arange(filesPerProc*nProcs, numFiles)
         fileIndices = np.concatenate((fileIndices, remainder))
      # endif

      for fileIndex in fileIndices:
         procMessage('Performing smoothing, RFI, and bandpass filtering on file {0} of {1}.'.format(
                     fileIndex, numFiles))
         spectTile = np.load(waterfallFiles[fileIndex], mmap_mode='r+')[fftLower:fftUpper]
      # endfor
   # endif

# end main_routine()


if __name__ = '__main__'
   main_routine(sys.argv[1:])
   sys.exit(0)
# endif
