import os
import sys
import numpy as np
from  mpi4py import MPI
import ConfigParser
import mmap
from optparse import OptionParser
import apputils 

def bpf(x, windows = 40):
    bp = savitzky_golay(x,windows,1)
    x2 = x / bp
    mask = np.where(snr(x2)>1)[0]
    mask2= np.zeros(x.shape[0])
    mask2[mask] = 1.
    y = np.ma.array(x, mask = mask2)
    bp = savitzky_golay(y,windows,1)
    fit = np.ma.polyfit(np.arange(len(y)),y,4)
    p = np.poly1d(fit)(np.arange(len(y)))[mask]
    bp = x
    bp[mask] = np.poly1d(fit)(np.arange(len(y)))[mask]
    bp = savitzky_golay(bp,windows,2)
    return bp

def fold(t,period,T0=0):
    time = np.arange(len(t))
    epoch = np.floor( 1.*(time - T0)/period )
    phase = 1.*(time - T0)/period - epoch
    foldt = t[np.argsort(phase)]
    return DecimateNPY(foldt, 1.*len(t)/period )


def RFImask(spr):#sp has shape[:,:]
    x = np.where(abs(spr.mean(1))>np.sort(spr.mean(1))[spr.shape[0]/2]+np.sort(spr.mean(1))[spr.shape[0]/2]-np.sort(spr.mean(1))[1])
    y = np.where(abs(spr.mean(0))>np.sort(spr.mean(0))[spr.shape[1]/2]+np.sort(spr.mean(0))[spr.shape[1]/2]-np.sort(spr.mean(0))[1])
    return [x[0],y[0]]

def massagesp(spectrometer, windows_x=43,windows_y=100):
    bp = bpf(spectrometer.mean(0),windows_x)
    spectrometer /= bp
    bl = bpf(spectrometer.mean(1),windows_y)
    spectrometer = (spectrometer.T - bl).T
    mask  = np.array ( RFImask(spectrometer) )
    mask2 = np.zeros((spectrometer.shape))
    mask2[mask[0],:] = 1.
    mask2[:,mask[1]] = 1.
    temp_spec = np.ma.array(spectrometer, mask = mask2 )
    mean = temp_spec.mean()
    spectrometer[mask[0],:] = mean
    spectrometer[:,mask[1]] = mean
    spectrometer -= mean
    return spectrometer


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
