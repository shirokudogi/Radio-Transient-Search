#from mpi4py import MPI
import os
import sys
import traceback
import mmap
import time
import getopt
import numpy
import mpi4py 
import mpi4py.MPI as MPI
from scipy.sparse import csr_matrix
import drx
import matplotlib.pyplot as plt
from ConfigParser import ConfigParser
from math import ceil
from math import floor
from optparse import OptionParser
import apputils
import waterfallinject



def main(argv):
   # Get multi-processing information.
   MPIComm = MPI.COMM_WORLD
   nProcs = MPIComm.Get_size()
   procRank = MPIComm.Get_rank()

   # Initialize command-line parser and then parse the command-line
   usage = " Usage: %prog [options] <radio filepath>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option("-t", "--integrate-time", dest="spectIntTime", default=1.0, type="float", 
                           action="store", 
                           help="Spectral integration time in milliseconds.", metavar="MSECS")
   cmdlnParser.add_option("-w", "--work-dir", dest="workDir", default=".",
                          action="store",
                          help="Working directory path.", metavar="PATH")
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", default="./radiotrans.ini",
                          action="store",
                          help="Common parameters file path.", metavar="PATH")
   cmdlnParser.add_option("-m", "--memory-limit", dest="memLimit", type=int, default=16, action="store",
                           help="Total memory usage limit, in MB, with minimum of 100 MB and a" + 
                           "maximum of 64000 MB, for all processes when generating spectrogram tiles.", 
                           metavar="MB")
   cmdlnParser.add_option("-l", "--label", dest="label", type="string", default=None, action="store",
                           help="Label attached to output files to help identify them to the user.",
                           metavar="LABEL")
   cmdlnParser.add_option("-e", "--enable-hann", dest="enableHann", action="store_true",
                           default=False, 
                           help="Apply Hann window to raw data DFTs to reduce harmonic leakage.")
   cmdlnParser.add_option('-u', '--data-utilization', dest='dataUtilFrac', default=1.0, type='float',
                           action='store',
                           help='Fraction (0 < abs(x) <= 1.0) of total spectrogram lines to create.',
                           metavar='FRAC')
   cmdlnParser.add_option("--inject-power", dest="injPower", default=10.0, type='float',
                           action='store',
                           help='Total spectral power of injected simulated burst signals.',
                           metavar='POWR')
   cmdlnParser.add_option("--inject-spectral-index", dest='injSpectIndex', default=0.0, type='float',
                           action='store',
                           help='Spectral index for injected simulated burst signals.',
                           metavar='INDEX')
   cmdlnParser.add_option('--num-injections', dest='numInjects', default=0, type='int', action='store',
                           help='Number of simulated burst signals to inject.', metavar='NUM')
   cmdlnParser.add_option('--injection-time-span', dest='injTimeSpan',
                           default=(None, None), action='store', nargs=2, type='float',
                           help='Time span in data, (BEGIN END) in seconds, containing injections.',
                           metavar='BEGIN END')
   cmdlnParser.add_option('--injection-dm-span', dest='injDMSpan',
                           default=(None, None), action='store', nargs=2, type='float',
                           help='Range of DMs, (BEGIN END) in pc cm^-3, spanned by injections',
                           metavar='BEGIN END')
   cmdlnParser.add_option('--inject-regular-times', dest='injRegularTimes', default=False,
                           action='store_true',
                           help='Inject simulated signals at regular time intervals.')
   cmdlnParser.add_option('--inject-regular-dms', dest='injRegularDMs', default=False,
                           action='store_true',
                           help='Inject simulated signals at regular DM intervals.')
   (cmdlnOpts, args) = cmdlnParser.parse_args(argv)
   if len(args) == 0:
      apputils.procMessage("waterfall.py: Must supply a path to the radio data file.", root=0,
                           msg_type='ERROR')
      apputils.MPIAbort(1)
   # endif
   spectIntegTime = cmdlnOpts.spectIntTime/1000.0
   memLimit = apputils.forceIntValue(cmdlnOpts.memLimit, 100, 64000)*1e6
   dataUtilFrac = cmdlnOpts.dataUtilFrac
   if abs(dataUtilFrac) > 1.0 or dataUtilFrac == 0.0:
      apputils.procMessage('waterfall.py: Invalid value for data utilization.  Forcing to 1.0', root=0,
                           msg_type='WARNING')
      dataUtilFrac = 1.0
   # endif
   #
   # Check waterfall injection specifications.
   cmdlnOpts.injectPower = numpy.maximum(0.0, cmdlnOpts.injPower)
   cmdlnOpts.numInjects = apputils.forceIntValue(cmdlnOpts.numInjects, 0, 50)
   cmdlnOpts.injectSpectIndex = numpy.maximum(-2.0, numpy.minimum(2.0, cmdlnOpts.injSpectIndex))
   if cmdlnOpts.injPower == 0.0:
      cmdlnOpts.numInjects = 0
   # endif


   # Obtain common parameters for the data reduction and subsequent parts of the transient search.
   rawDataFramesPerBeam = 4   # Number of data frames per beam in the raw data file.
   rawDataFilePath = args[0]
   rawDataFilename = os.path.basename(os.path.splitext(rawDataFilePath)[0])
   rawDataFileSize = os.path.getsize(rawDataFilePath)
   rawDataFrameSize = drx.FrameSize
   rawDataNumFrames = int(rawDataFileSize/rawDataFrameSize)
   rawDataNumFramesPerTune = int(rawDataNumFrames/rawDataFramesPerBeam)
   rawDataSamplesPerFrame = 4096
   LFFT = rawDataSamplesPerFrame # Length of the FFT.
   DFTLength = LFFT

   # Open the raw data file.
   try:
      rawDataFile = open(rawDataFilePath, 'rb')
   except Exception as anError:
      traceback.print_tb(sys.exc_info()[2], file=sys.stderr)
      apputils.procMessage('waterfall.py: {0}'.format(str(anError)), msg_type='ERROR')
      apputils.procMessage('waterfall.py: {0} not found or could not be opened.'.format(rawDataFilePath),
                           msg_type='ERROR')
      apputils.MPIAbort(1)
   # endtry
   # Obtain metadata for the raw data file.
   try:
      junkFrame = drx.readFrame(rawDataFile)
      try:
         # Obtain sample rate and beam number.  NOTE: a single raw data file is associated with a single
         # beam.
         rawDataSampleRate = junkFrame.getSampleRate()
         rawDataSampleTime = 1.0/rawDataSampleRate
         rawDataFrameTime = rawDataSamplesPerFrame*rawDataSampleTime
         rawDataBeamID, tune, pol = junkFrame.parseID()
         pass
      except ZeroDivisionError as anError:
         traceback.print_tb(sys.exc_info()[2], file=sys.stderr)
         apputils.procMessage('waterfall.py: Zero division error computing sample rate.',
                              msg_type='ERROR')
         rawDataFile.close()
         apputils.MPIAbort(1)
      # endtry

      # Obtain the tuning frequencies by reading the first 4 frames.
      rawDataFile.seek(-rawDataFrameSize, os.SEEK_CUR)
      rawDataTuningFreq0 = 0.0
      rawDataTuningFreq1 = 0.0
      for i in xrange(rawDataFramesPerBeam):
         junkFrame = drx.readFrame(rawDataFile)
         (beam, tune, pol) = junkFrame.parseID()
         if pol == 0:
            if tune == 0:
                  rawDataTuningFreq0 = junkFrame.getCentralFreq()
            else:
                  rawDataTuningFreq1 = junkFrame.getCentralFreq()
            # endif
         # endif
      # endfor
      rawDataFile.seek(-rawDataFramesPerBeam*rawDataFrameSize, os.SEEK_CUR)
   except Exception as anError:
      traceback.print_tb(sys.exc_info()[2], file=sys.stderr)
      apputils.procMessage('waterfall.py: {0}'.format(str(anError)), msg_type='ERROR')
      apputils.procMessage('waterfall.py: Could not obtain metadata for radio data file.',
                           msg_type='ERROR')
      rawDataFile.close()
      apputils.MPIAbort(1)
   # endtry

   # Compute data reduction parameters.
   numDFTsPerSpectLine = max(1, int(spectIntegTime/rawDataFrameTime))
   rawDataNumSpectLines = max(1, int( rawDataNumFramesPerTune/numDFTsPerSpectLine ))
   numSpectLines = max(1, int( abs(dataUtilFrac)*rawDataNumSpectLines ))
   memSpectLinesPerProc = int( memLimit/(2*nProcs*LFFT*numpy.dtype(numpy.float32).itemsize) )
   numSpectLinesPerProc = min(int(numSpectLines/nProcs), memSpectLinesPerProc)
   
   # Have process 0 output common parameters to the common parameters file to avoid collision issues.
   if procRank == 0:
      try:
         commConfigFile = open(cmdlnOpts.configFilepath, 'w')
         commConfigObj = ConfigParser()
         commConfigObj.add_section('Raw Data')
         commConfigObj.add_section('Reduced DFT Data')
         commConfigObj.add_section('Run')
         commConfigObj.set('Raw Data', 'filepath', rawDataFilePath)
         commConfigObj.set('Raw Data', 'filename', rawDataFilename)
         commConfigObj.set('Raw Data', 'filesize', rawDataFileSize)
         commConfigObj.set('Raw Data', 'framesize', rawDataFrameSize)
         commConfigObj.set('Raw Data', 'numframes', rawDataNumFrames)
         commConfigObj.set('Raw Data', 'numframesperbeam', rawDataFramesPerBeam)
         commConfigObj.set('Raw Data', 'numframespertune', rawDataNumFramesPerTune)
         commConfigObj.set('Raw Data', 'numsamplesperframe', rawDataSamplesPerFrame)
         commConfigObj.set('Raw Data', 'numspectrogramlines', rawDataNumSpectLines)
         commConfigObj.set('Raw Data', 'samplerate', rawDataSampleRate)
         commConfigObj.set('Raw Data', 'sampletime', rawDataSampleTime)
         commConfigObj.set('Raw Data', 'frametime', rawDataFrameTime)
         commConfigObj.set('Raw Data', 'tuningfreq0', rawDataTuningFreq0)
         commConfigObj.set('Raw Data', 'tuningfreq1', rawDataTuningFreq1)
         commConfigObj.set('Raw Data', 'beam', rawDataBeamID)
         commConfigObj.set('Raw Data', 'datautilfrac', dataUtilFrac)
         commConfigObj.set('Reduced DFT Data', 'DFTlength', DFTLength)
         commConfigObj.set('Reduced DFT Data', 'integrationtime', spectIntegTime)
         commConfigObj.set('Reduced DFT Data', 'numspectrogramlines', numSpectLines)
         commConfigObj.set('Reduced DFT Data', 'numDFTsperspectrogramline', numDFTsPerSpectLine)
         commConfigObj.set('Reduced DFT Data', 'numspectrogramlinespertile', numSpectLinesPerProc)
         commConfigObj.set('Reduced DFT Data', 'numspectrogramlinesresiduetile', 
                              numSpectLines - nProcs*numSpectLinesPerProc)
         commConfigObj.set('Reduced DFT Data', 'enablehannwindow', cmdlnOpts.enableHann)
         commConfigObj.set('Run', 'label', cmdlnOpts.label)
         if cmdlnOpts.numInjects != 0:
            commConfigObj.add_section("Injections")
            commConfigObj.set("Injections", "numinjects", cmdlnOpts.numInjects)
            commConfigObj.set("Injections", "injectpower", cmdlnOpts.injectPower)
            commConfigObj.set("Injections", "injectspectralindex", cmdlnOpts.injectSpectIndex)
            commConfigObj.set("Injections", "injecttemporalprofile", cmdlnOpts.injTimeSpan)
            commConfigObj.set("Injections", "injectdmprofile", cmdlnOpts.injDMSpan)
         # endif
         commConfigObj.write(commConfigFile)
         commConfigFile.flush()
         commConfigFile.close()
      except Exception as anError:
         traceback.print_tb(sys.exc_info()[2], file=sys.stderr)
         apputils.procMessage('waterfall.py: {0}'.format(str(anError)), root=0, msg_type='ERROR')
         apputils.procMessage('waterfall.py: Could not open or write common parameters file.', root=0,
                              msg_type='ERROR')
         commConfigFile.close()
         MPIComm.Abort(1)
      # endtry
   # endif

   # Each process creates spectrogram tiles that are limited in size by the memory limits specified by
   # the user.  So we need to figure out how each process will step through the raw data file for each
   # spectrogram tile that it is supposed to create.
   fileStep = 4*rawDataFrameSize*numDFTsPerSpectLine*numSpectLinesPerProc
   fileOffset = fileStep*procRank
   endFileOffset = rawDataFileSize
   if dataUtilFrac < 0.0:
      numSkipSpectLines = int( numpy.ceil( (1 + dataUtilFrac)*rawDataNumSpectLines ) )
      fileOffset = fileOffset + 4*rawDataFrameSize*numDFTsPerSpectLine*numSkipSpectLines 
   else:
      if dataUtilFrac < 1.0 :
         endFileOffset = numpy.ceil(dataUtilFrac*rawDataFileSize)
      # endif
   # endif

   # Precompute indices for the spectrogram tile and counting the raw DFTs.
   lineIndices = range(numSpectLinesPerProc)
   dftIndices = range(numDFTsPerSpectLine)

   # Build the working arrays for the computing DFTs, integrating the DFTs into a power spectrum, and
   # composing a single spectrogram tile.
   powerDFT0 = numpy.zeros(DFTLength, dtype=numpy.float32)
   powerDFT1 = numpy.zeros(DFTLength, dtype=numpy.float32)
   spectTile0 = numpy.ndarray(shape=(numSpectLinesPerProc, DFTLength), dtype=numpy.float32)
   spectTile1 = numpy.ndarray(shape=(numSpectLinesPerProc, DFTLength), dtype=numpy.float32)

   # Compute the DFT of the Hann window, if enabled.
   hannWindow = None
   if cmdlnOpts.enableHann:
      hannWindow = 2*numpy.pi*numpy.arange(rawDataSamplesPerFrame, 
                                           dtype=numpy.float32)/(rawDataSamplesPerFrame - 1)
      hannWindow[:] = 0.5*(1 - numpy.cos(hannWindow[:]))
   # endif

   # If waterfall injections enabled, create waterfall injections.
   injSpect0 = None  # Injection spectrogram for tuning 0.
   injSpect1 = None  # Injection spectrogram for tuning 1.
   if cmdlnOpts.numInjects > 0:
      if procRank == 0:
         apputils.procMessage('waterfall.py: Generating waterfall injections.', root=0)
         bandwidth = rawDataSampleRate/1.0e6
         channelWidth = bandwidth/DFTLength

         apputils.procMessage('waterfall.py: Generating waterfall injections for tuning 0.', root=0)
         freqs = apputils.computeFreqs(rawDataTuningFreq0/1.0e6, bandwidth, numBins=DFTLength)
         injSpect0 = waterfallinject.create_injections(freqs, channelWidth, rawDataNumFramesPerTune,
                                                       rawDataFrameTime, cmdlnOpts.injPower*(4.0*LFFT),
                                                       cmdlnOpts.injSpectIndex,
                                                       cmdlnOpts.injTimeSpan, cmdlnOpts.injDMSpan,
                                                       cmdlnOpts.numInjects, cmdlnOpts.injRegularTimes,
                                                       cmdlnOpts.injRegularDMs, root=0)

         apputils.procMessage('waterfall.py: Generating waterfall injections for tuning 1.', root=0)
         freqs = apputils.computeFreqs(rawDataTuningFreq1/1.0e6, bandwidth, numBins=DFTLength)
         injSpect1 = waterfallinject.create_injections(freqs, channelWidth, rawDataNumFramesPerTune,
                                                       rawDataFrameTime, cmdlnOpts.injPower*(4.0*LFFT),
                                                       cmdlnOpts.injSpectIndex,
                                                       cmdlnOpts.injTimeSpan, cmdlnOpts.injDMSpan,
                                                       cmdlnOpts.numInjects, cmdlnOpts.injRegularTimes,
                                                       cmdlnOpts.injRegularDMs, root=0)
      # endif
      # Broadcast injections to other processes.
      try:
         apputils.procMessage('waterfall.py: Broadcasting tuning 0 injections to processes.', root=0)
         injSpect0 = apputils.MPIBcast_SCIPY_Sparse_Matrix(injSpect0, root=0)
         apputils.procMessage('waterfall.py: Broadcasting tuning 1 injections to processes.', root=0)
         injSpect1 = apputils.MPIBcast_SCIPY_Sparse_Matrix(injSpect1, root=0)
      except Exception as anError:
         traceback.print_tb(sys.exc_info()[2], file=sys.stderr)
         apputils.procMessage('waterfall.py: {0}'.format(str(anError)), msg_type='ERROR')
         apputils.procMessage('waterfall.py: Could not broadcast sparse matrix to processes',
                              msg_type='ERROR')
         apputils.MPIAbort(1)
      # endtry
   # endif

   # Create spectrogram tiles.
   lineOffset = numSpectLinesPerProc*procRank
   injOffset = lineOffset*numDFTsPerSpectLine
   normFactor = (4.0*LFFT*numDFTsPerSpectLine)
   while fileOffset < endFileOffset:
      rawDataFile.seek(fileOffset, os.SEEK_CUR)
      apputils.procMessage("Integrating lines {start} to {end}...".format(start=lineOffset,
                           end=lineOffset + numSpectLinesPerProc - 1, tile=lineOffset), root=0)
      for i in lineIndices:
         apputils.procMessage("Integrating {line} of {total} from lineOffset = {tile}...".format(line=i+1, 
                              tile=lineOffset, total=numSpectLinesPerProc), root=0)
         for j in dftIndices:
            # Read 4 frames from the raw data and compute their DFTs.
            k = 0
            while k < rawDataFramesPerBeam:
               # Compute the DFT of the current frame.
               currFrame = drx.readFrameOpt(rawDataFile)
               if currFrame is not None:
                  if cmdlnOpts.enableHann:
                     timeData = currFrame.data.iq*hannWindow
                  else:
                     timeData = currFrame.data.iq
                  # endif
                  frameDFT = numpy.fft.fftshift(numpy.fft.fft(timeData))
                  # Determine the tuning of the computed DFT and add its power to the appropriate power DFT.
                  (beam, tune, pol) = currFrame.parseID()
                  if tune == 0:
                     powerDFT0[:] += frameDFT.real[:]**2 + frameDFT.imag[:]**2
                  else:
                     powerDFT1[:] += frameDFT.real[:]**2 + frameDFT.imag[:]**2
                  # endif
                  k += 1
               else:
                  k = rawDataFramesPerBeam
               # endif
            # endwhile
            
            # Add waterfall injections, if we have any.
            if cmdlnOpts.numInjects > 0:
               # Determine where to add injection power.
               injIndex = injOffset + i*numDFTsPerSpectLine + j
               # Add injection power, if there is any.
               if injSpect0 is not None:
                  powerDFT0[:] += injSpect0[injIndex, :].toarray().flatten()
               # endif
               if injSpect1 is not None:
                  powerDFT1[:] += injSpect1[injIndex, :].toarray().flatten()
               # endif
         # endfor
         
         spectTile0[i,:] = powerDFT0[:]/(normFactor)
         spectTile1[i,:] = powerDFT1[:]/(normFactor)

         # Reset for the next integration of power DFTs.
         powerDFT0.fill(0)
         powerDFT1.fill(0)
      # endfor

      # Write tuning 0  spectrogram tile to numpy file.
      apputils.procMessage("Writing tuning 0 spectrogram tile lineOffset={tile}...".format(tile=lineOffset))
      outFilepath = apputils.createWaterfallFilepath(tile=lineOffset, tuning=0, beam=rawDataBeamID,
                                            label=cmdlnOpts.label, workDir=cmdlnOpts.workDir)
      numpy.save(outFilepath, spectTile0)
      # Write tuning 1 spectrogram tile to numpy file.
      apputils.procMessage("Writing tuning 1 spectrogram tile lineOffset={tile}...".format(tile=lineOffset))
      outFilepath = apputils.createWaterfallFilepath(tile=lineOffset, tuning=1, beam=rawDataBeamID,
                                            label=cmdlnOpts.label, workDir=cmdlnOpts.workDir)
      numpy.save(outFilepath, spectTile1)


      # Compute the fileOffset in the raw data from which we will create the next spectrogram tile for
      # this process and determine if that is past the end of the file (in which case, we stop).
      fileOffset = fileOffset + fileStep*nProcs
      lineOffset = lineOffset + numSpectLinesPerProc*nProcs
      if fileOffset < endFileOffset:
         # Compute how much remains of the raw data file and determine whether there is enough to create
         # a full spectrogram tile or whether we need to create a smaller tile.
         fileRemain = endFileOffset - fileOffset - 1
         if fileRemain > 0 and fileRemain < fileStep:
            numFramesRemain = int( floor(fileRemain/rawDataFrameSize) )
            numDFTsRemain = int( floor(numFramesRemain/4) )
            numSpectLinesPerProc = int( floor(numDFTsRemain/numDFTsPerSpectLine) )
            # Resize the spectrogram tile arrays and indexing to the new, smaller size.
            lineIndices = range(numSpectLinesPerProc)
            spectTile0.resize((numSpectLinesPerProc, DFTLength))
            spectTile1.resize((numSpectLinesPerProc, DFTLength))
         # endif
      # endif
   # endwhile
   apputils.procMessage("Done creating waterfall!")
# end main()


if __name__ == "__main__":
   main(sys.argv[1:])
   sys.exit(0)
# endif
