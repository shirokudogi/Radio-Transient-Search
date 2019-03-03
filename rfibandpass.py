import os
import sys
import numpy as np
from  mpi4py import MPI
import tempfile
import mmap
from optparse import OptionParser
from ConfigParser import ConfigParser
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
   sprMedian0 = sprSort0[sprSort0.shape[0]/2]

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
   cmdlnParser.add_option('--bandpass-window', dest='bpWindow', type='int', default=11,
                           help='Bandpass smoothing window size. Must be positive odd number.', 
                           metavar='INT')
   cmdlnParser.add_option('--baseline-window', dest='blWindow', type='int', default=51,
                           help='Baseline smoothing window size. Must be positive odd number', 
                           metavar='INT')
   cmdlnParser.add_option('--tuning1', dest='enableTuning1', default=False, action='store_true',
                           help='Flag denoting tuning 1.')
   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)

   lowerFFTIndex = apputils.forceIntValue(cmdlnOpts.lowerFFTIndex, 0, 4094)
   upperFFTIndex = apputils.forceIntValue(cmdlnOpts.upperFFTIndex, 0, 4094)
   bpWindow = apputils.forceIntValueOdd(cmdlnOpts.bpWindow, 1, 9999, align=1)
   blWindow = apputils.forceIntValueOdd(cmdlnOpts.blWindow, 1, 9999, align=1)

   # Notify user if smoothing window values need to be adjusted.
   if bpWindow != cmdlnOpts.bpWindow:
      apputils.procMessage('rfibandpass.py: Bandpass window adjusted to ' +
                           ' {value} (odd value required)'.format(value=bpWindow), 
                           msg_type='WARNING', root=0)
   # endif
   if blWindow != cmdlnOpts.blWindow:
      apputils.procMessage('rfibandpass.py: Baseline window adjusted to ' +
                           ' {value} (odd value required)'.format(value=blWindow),
                           msg_type='WARNING', root=0)
   # endif

   # Check that lower FFT index is less than the upper FFT index.
   if upperFFTIndex <= lowerFFTIndex:
      apputils.procMessage('rfibandpass.py:  Upper FFT cutoff must be greater than lower FFT cutoff',
                  root=0, msg_type='ERROR')
      sys.exit(1)
   # endif
   # Check that we have a spectrogram file specified.
   if len(cmdlnArgs) > 0:
      spectFilepath = cmdlnArgs[0]
   else:
      apputils.procMessage('rfibandpass.py:  Must specify a spectrogram file.',
                  root=0, msg_type='ERROR')
      sys.exit(1)
   # endif


   # Read common parameters file.
   try:
      commConfigFile = open(cmdlnOpts.configFilepath,'r')
      commConfigObj = ConfigParser()
      commConfigObj.readfp(commConfigFile, cmdlnOpts.configFilepath)

      DFTLength = commConfigObj.getint("Reduced DFT Data", "dftlength")
      commConfigFile.close()
      # If this is the rank 0 process, update the common parameters file with the RFI and bandpass
      if rank == 0:
         try:
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
         except:
            apputils.procMessage('rfibandpass.py: Could not update common ' + 
                        'parameters file {file}'.format(file=cmdlnOpts.configFilepath), 
                        msg_type='ERROR')
            sys.exit(1)
         # endtry
      # endif
   except:
      apputils.procMessage('rfibandpass.py: Could not find or open common ' + 
                           'parameters file {file}'.format(file=cmdlnOpts.configFilepath), 
                           msg_type='ERROR')
      sys.exit(1)
   # endtry

   # Load the spectrogram file and determine partitioning to each process..
   segmentSize = None
   segmentOffset = None
   spectrogram = None
   numSpectLines = 0
   if rank == 0:
      # Load spectrogram.
      apputils.procMessage('rfibandpass.py: Loading spectrogram (may take a while)', root=0)
      spectrogram = np.load(spectFilepath, mmap_mode='r')
      numSpectLines = spectrogram.shape[0]

      # Determine partitioning of spectrogram to each processes.
      segmentSize = np.zeros(nProcs, dtype=np.int64)
      segmentOffset = np.zeros(nProcs, dtype=np.int64)
      segmentSize[1:] = np.int64( numSpectLines/nProcs )
      segmentSize[0] = np.int64( numSpectLines - (nProcs - 1)*segmentSize[1] )
      segmentOffset[0] = 0
      segmentOffset[1:] = segmentSize[0] + segmentSize[1]*np.arange(nProcs - 1, dtype=np.int64)
   # endif
   # Distribute spectrogram partitions to processes.
   apputils.procMessage('rfibandpass.py: Distributing spectrogram segments', root=0)
   segmentSize = MPIComm.bcast(segmentSize, root=0)
   segmentOffset = MPIComm.bcast(segmentOffset, root=0)
   (tempFD, tempFilepath) = tempfile.mkstemp(prefix='tmp', suffix='.dtmp', dir=cmdlnOpts.workDir)
   segment = np.memmap(filename=tempFilepath, shape=(segmentSize[rank], DFTLength), 
                              dtype=np.float32, mode='w+')
   MPIComm.Scatterv([spectrogram, segmentSize*DFTLength, segmentOffset*DFTLength, MPI.FLOAT], 
                    [segment, segmentSize[rank]*DFTLength, MPI.FLOAT],
                    root=0)

   # Trim spectrogram segment to bandpass and perform RFI filtering on it.
   bandpassLength = upperFFTIndex - lowerFFTIndex + 1
   (tempFD, tempFilepath) = tempfile.mkstemp(prefix='tmp', suffix='.dtmp', dir=cmdlnOpts.workDir)
   rfibpSegment = np.memmap(filename=tempFilepath, shape=(segmentSize[rank], bandpassLength), 
                              dtype=np.float32, mode='w+')
   apputils.procMessage('rfibandpass.py: Performing RFI and bandpass filtration on segment.')
   rfibpSegment[:, :] = massagesp(segment[ : , lowerFFTIndex:upperFFTIndex + 1], 
                                    bpWindow, blWindow)[:, :]

   # Gather the pieces of the RFI-bandpass filtered spectrogram and integrate them into the final
   # RFI-bandpass filtered spectrogram.
   apputils.procMessage('rfibandpass.py: Re-integrating segments of filtered spectrogram', root=0)
   rfibpSpectrogram = None
   if rank == 0:
      (tempFD, tempFilepath) = tempfile.mkstemp(prefix='tmp', suffix='.dtmp', dir=cmdlnOpts.workDir)
      rfibpSpectrogram = np.memmap(filename=tempFilepath, shape=(numSpectLines, bandpassLength), 
                                 dtype=np.float32, mode='w+')
   # endif
   MPIComm.Gatherv([rfibpSegment, segmentSize[rank]*bandpassLength, MPI.FLOAT],
                   [rfibpSpectrogram, segmentSize*bandpassLength, segmentOffset*bandpassLength, 
                     MPI.FLOAT],
                   root=0)

   # Save the RFI-bandpass filtered spectrogram to file.
   if rank == 0:
      apputils.procMessage('rfibandpass.py: Writing RFI and bandpass filtered spectrogram.', root=0)
      np.save(cmdlnOpts.outFilepath, rfibpSpectrogram)
   # endif

# end main_routine()


if __name__ == '__main__':
   main_routine(sys.argv[1:])
   sys.exit(0)
# endif
