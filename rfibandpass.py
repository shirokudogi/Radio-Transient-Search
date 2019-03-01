import os
import sys
import numpy as np
from  mpi4py import MPI
import ConfigParser
import mmap
from optparse import OptionParser
import apputils 

def bpf(x, windows = 40):
   x2 = x/apputils.savitzky_golay(x, windows, 1)
   mask = apputils.snr(x2) > 1
   y = np.ma.array(x, mask = mask)
   indices = np.arange(len(y))
   fit = np.ma.polyfit(indices, y, 4)
   x[mask] = np.poly1d(fit)(indices)[mask]
   return apputils.savitzky_golay(x, windows, 2)
# end bpf()


def RFImask(spr):
   sprMean0 = spr.mean(0)
   sprSort0 = np.sort(sprMean0)
   sprMedian0 = sprSort0[sprSort.shape[0]/2]

   sprMean1 = spr.mean(1)
   sprSort1 = np.sort(sprMean1)
   sprMedian1 = sprSort1[sprSort1.shape[0]/2]

   x = np.where(abs(sprMean1) > 2*sprMedian1 - sprSort1[1])
   y = np.where(abs(sprMean0) > 2*sprMedian0 - sprSort0[1])
   return (x[0], y[0])
# end RFImask()


def massagesp(spectrometer, windows_x=43,windows_y=100):
   spectrometer /= bpf(spectrometer.mean(0), windows_x)
   spectrometer = (spectrometer.T - bpf(spectrometer.mean(1), windows_y)).T

   mask  = np.array ( RFImask(spectrometer) )
   mask2 = np.zeros((spectrometer.shape))
   mask2[mask[0], :] = 1.
   mask2[:, mask[1]] = 1.

   temp_spec = np.ma.array(spectrometer, mask = mask2 )
   mean = temp_spec.mean()

   spectrometer[:,:] = spectrometer[:,:] - mean
   spectrometer[mask[0],:] = 0.0
   spectrometer[:,mask[1]] = 0.0
   return spectrometer
# end massagesp()


def main_routine(args):
   MPIComm = MPI.COMM_WORLD
   rank = MPIComm.Get_rank()
   nProcs = MPIComm.Get_size()

   # Setup and parse commandline.
   usage = "USAGE: %prog [options] <spectrogram file path>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option('-l', '--lower-fft-index', dest='lowerFFTIndex', type='int', default=0,
                           help='Lower FFT index (between 0 and 4094) for bandpass filtering.', 
                           metavar='INDEX')
   cmdlnParser.add_option('-u', '--upper-fft-index', dest='upperFFTIndex', type='int', default=4094,
                           help='Upper FFT index (between 0 and 4094) for bandpass filtering.', 
                           metavar='INDEX')
   cmdlnParser.add_option('-w', '--work-dir', dest='workDir', type='string', default='.',
                           help='Path to the working directory.', metavar='PATH')
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", default="./radiotrans.ini",
                          action="store",
                          help="Common parameters file path.", metavar="PATH")
   cmdlnParser.add_option('-o', '--output-file', dest='outFilepath', type='string', 
                           default='./rfibp-spectrogram.npy',
                           help='Path to the output file.',
                           metavar='PATH')
   cmdlnParser.add_option('-bp', '--bandpass-window', dest='bpWindow', type='int', default=10,
                           help='Bandpass smoothing window size.', metavar='INT')
   cmdlnParser.add_option('-bl', '--baseline-window', dest='blWindow', type='int', default=50,
                           help='Baseline smoothing window size.', metavar='INT')
   cmdlnParser.add_option('--tuning1', dest='enableTuning1', default=False, action='store_true',
                           help='Flag denoting tuning 1.')
   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)

   lowerFFTIndex = forceIntValue(cmdlnOpts.lowerFFTIndex, 0, 4094)
   upperFFTIndex = forceIntValue(cmdlnOpts.upperFFTIndex, 0, 4094)
   bpWindow = forceIntValue(cmdlnOpts.bpWindow, 1, 9999)
   blWindow = forceIntValue(cmdlnOpts.blWindow, 1, 9999)

   # Check that lower FFT index is less than the upper FFT index.
   if upperFFTIndex <= lowerFFTIndex:
      procMessage('rfibandpass.py:  Upper FFT cutoff must be greater than lower FFT cutoff',
                  root=0, msg_type='ERROR')
      sys.exit(1)
   # endif
   # Check that we have a spectrogram file specified.
   if len(cmdlnArgs) > 0:
      spectFilepath = cmdlnArgs[0]
   else:
      procMessage('rfibandpass.py:  Must specify a spectrogram file.',
                  root=0, msg_type='ERROR')
      sys.exit(1)
   # endif

   # Read common parameters file.
   try:
      commConfigFile = open(cmdlnOpts.configFilepath,'r')
      commConfigObj = ConfigParser()
      commConfigObj.readfp(commConfigFile, cmdlnOpts.configFilepath)

      DFTLength = commConfigObj.getint("Reduced DFT Data", "dftlength")
      commFile.close()
      # If this is the rank 0 process, update the common parameters file with the RFI and bandpass
      if rank == 0:
         commConfigFile = open(cmdlnOpts.configFilepath,'w')
         if not commConfigObj.has_section("RFI Bandpass"):
            commConfigObj.add_section("RFI Bandpass")
         # endif
         if cmdlnOpts.enableTuning1:
            commConfigObj.set("RFI Bandpass", "lowerfftindex1", lowerFFTIndex)
            commConfigObj.set("RFI Bandpass", "upperfftindex1", upperFFTIndex)
         else:
            commConfigObj.set("RFI Bandpass", "lowerfftindex0", lowerFFTIndex)
            commConfigObj.set("RFI Bandpass", "upperfftindex0", upperFFTIndex)
         # endif
         commConfigObj.set("RFI Bandpass", "bandpasswindow", bpWindow)
         commConfigObj.set("RFI Bandpass", "baselinewindow", blWindow)
         commConfigObj.write(commConfigFile)
         commConfigFile.flush()
         commConfigFile.close()
      # endif
      # filtration parameters.
   except:
   # endtry

   # Load the spectrogram file and determine the partition to each process..
   linesPerProc = None
   spectrogram = None
   numSpectLines = 0
   if rank == 0:
      # Load spectrogram.
      spectrogram = np.load(spectFilepath, mmap_mode='r')
      numSpectLines = spectrogram.shape[0]

      # Determine partitioning of spectrogram to each processes.
      linesPerProc = np.zeros(nProcs, dtype=np.int32)
      segmentSize = np.int(numSpectLines/nProcs)
      linesPerProc[0] = numSpectLines - (nProcs - 1)*segmentSize
      linesPerProc[1:] = segmentSize
   # endif

   # Distribute parts of the spectrogram for smoothing
   linesPerProc = MPIComm.bcast(linesPerProc, root=0)
   spectSegment = np.zeros(linesPerProc[rank]*DFTLength, 
                           dtype=np.float32).reshape((linesPerProc[rank], DFTLength))
   MPIComm.Scatterv([spectrogram, numSpectLines*DFTLength, MPI.FLOAT], 
                    [spectSegment, linesPerProc[rank]*DFTLength, MPI.FLOAT],
                    root=0)

   # Trim to bandpass and perform smoothing on the spectrogram segment.
   procMessage('rfibandpass.py: Performing RFI and bandpass filtration.', root=0)
   spectSegment = massagesp(spectSegment[ : , lowerFFTIndex:upperFFTIndex], bpWindow, blWindow)

   # Gather the pieces of the smoothed spectrogram
   bandpassLength = upperFFTIndex - lowerFFTIndex
   if rank == 0:
      spectrogram = np.zeros(numSpectLines*bandpassLength, 
                             dtype=np.float32).reshape((numSpectLines, bandpassLength))
   # endif
   MPIComm.Gatherv([spectSegment, linesPerProc[rank]*bandpassLength, MPI.FLOAT],
                   [spectrogram, numSpectLines*bandpassLength, MPI.FLOAT],
                   root=0)

   # Save the spectrogram to file.
   if rank == 0:
      procMessage('rfibandpass.py: Writing RFI and bandpass filtered spectrogram.', root=0)
      np.save(cmdlnOpts.outFilepath, spectrogram)
   # endif

# end main_routine()


if __name__ = '__main__'
   main_routine(sys.argv[1:])
   sys.exit(0)
# endif
