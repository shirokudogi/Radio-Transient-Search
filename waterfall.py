#from mpi4py import MPI
import mpi4py 
import mpi4py.MPI as MPI
import os
import sys
import numpy
import getopt
import drx
import time
import matplotlib.pyplot as plt
from ConfigParser import ConfigParser
import mmap
from math import ceil
from math import floor
from optparse import OptionParser
from apputils import procMessage
from apputils import Decimate
from apputils import forceIntValue
from apputils import DEBUG_MSG
from apputils import createWaterfallFilepath



def main_orig(args):
   totalrank = 12
   comm  = MPI.COMM_WORLD
   rank  = comm.Get_rank()
   t0 = time.time()
   nChunks = 10000 #the temporal shape of a file.
   LFFT = 4096 #Length of the FFT.4096 is the size of a frame readed.
   nFramesAvg = 1*4*LFFT/4096 # the intergration time under LFFT, 4 = beampols = 2X + 2Y (high and low tunes)
   
   #for offset_i in range(4306, 4309):# one offset = nChunks*nFramesAvg skiped
   for offset_i in range(100, 1000 ):# one offset = nChunks*nFramesAvg skiped
      offset_i = 1.*totalrank*offset_i + rank
      offset = nChunks*nFramesAvg*offset_i
      # Build the DRX file
      try:
         fh = open(getopt.getopt(args,':')[1][0], "rb")
         nFramesFile = os.path.getsize(getopt.getopt(args,':')[1][0]) / drx.FrameSize #drx.FrameSize = 4128
      except:
         print getopt.getopt(args,':')[1][0],' not found'
         sys.exit(1)
      try:
         junkFrame = drx.readFrame(fh)
         try:
            srate = junkFrame.getSampleRate()
            pass
         except ZeroDivisionError:
            print 'zero division error'
            break
      except errors.syncError:
         print 'assuming the srate is 19.6 MHz'
         fh.seek(-drx.FrameSize+1, 1)
      fh.seek(-drx.FrameSize, 1)
      beam,tune,pol = junkFrame.parseID()
      beams = drx.getBeamCount(fh)
      tunepols = drx.getFramesPerObs(fh)
      tunepol = tunepols[0] + tunepols[1] + tunepols[2] + tunepols[3]
      beampols = tunepol
      if offset != 0:
         fh.seek(offset*drx.FrameSize, 1)
      if nChunks == 0:
         nChunks = 1
      nFrames = nFramesAvg*nChunks
      centralFreq1 = 0.0
      centralFreq2 = 0.0
      for i in xrange(4):
         junkFrame = drx.readFrame(fh)
         b,t,p = junkFrame.parseID()
         if p == 0 and t == 0:
            try:
               centralFreq1 = junkFrame.getCentralFreq()
            except AttributeError:
               from dp import fS
               centralFreq1 = fS * ((junkFrame.data.flags[0]>>32) & (2**32-1)) / 2**32
         elif p == 0 and t == 2:
            try:
               centralFreq2 = junkFrame.getCentralFreq()
            except AttributeError:
               from dp import fS
               centralFreq2 = fS * ((junkFrame.data.flags[0]>>32) & (2**32-1)) / 2**32
         else:
            pass
      fh.seek(-4*drx.FrameSize, 1)
      # Sanity check
      if nFrames > (nFramesFile - offset):
         raise RuntimeError("Requested integration time + offset is greater than file length")
      # Master loop over all of the file chunks
      freq = numpy.fft.fftshift(numpy.fft.fftfreq(LFFT, d = 1.0/srate))
      tInt = 1.0*LFFT/srate
      print 'Temporal resl = ',tInt
      print 'Channel width = ',1./tInt
      freq1 = freq+centralFreq1
      freq2 = freq+centralFreq2
      #print tInt,freq1.mean(),freq2.mean()
      masterSpectra = numpy.zeros((nChunks, 2, LFFT-1))
      for i in xrange(nChunks):
         # Find out how many frames remain in the file.  If this number is larger
         # than the maximum of frames we can work with at a time (nFramesAvg),
         # only deal with that chunk
         framesRemaining = nFrames - i*nFramesAvg
         if framesRemaining > nFramesAvg:
            framesWork = nFramesAvg
         else:
            framesWork = framesRemaining
         #if framesRemaining%(nFrames/10)==0:
         #  print "Working on chunk %i, %i frames remaining" % (i, framesRemaining)
         count = {0:0, 1:0, 2:0, 3:0}
         data = numpy.zeros((4,framesWork*4096/beampols), dtype=numpy.csingle)
         # If there are fewer frames than we need to fill an FFT, skip this chunk
         if data.shape[1] < LFFT:
            print 'data.shape[1]< LFFT, break'
            break
         # Inner loop that actually reads the frames into the data array
         for j in xrange(framesWork):
            # Read in the next frame and anticipate any problems that could occur
            try:
               cFrame = drx.readFrame(fh, Verbose=False)
            except errors.eofError:
               print "EOF Error"
               break
            except errors.syncError:
               print "Sync Error"
               continue
            beam,tune,pol = cFrame.parseID()
            if tune == 0:
               tune += 1
            aStand = 2*(tune-1) + pol
            data[aStand, count[aStand]*4096:(count[aStand]+1)*4096] = cFrame.data.iq
            count[aStand] +=  1
         # Calculate the spectra for this block of data
         masterSpectra[i,0,:] = ((numpy.fft.fftshift(numpy.abs(numpy.fft.fft2(data[:2,:]))[:,1:]))**2.).mean(0)/LFFT/2. #in unit of energy
         masterSpectra[i,1,:] = ((numpy.fft.fftshift(numpy.abs(numpy.fft.fft2(data[2:,:]))[:,1:]))**2.).mean(0)/LFFT/2. #in unit of energy
         # Save the results to the various master arrays
         #print masterSpectra.shape
         #numpy.save('data',data)
         #sys.exit()
         #if i % 100 ==1 :
         #  print i, ' / ', nChunks
      outname = "%s_%i_fft_offset_%.9i_frames" % (getopt.getopt(args,':')[1][0], beam,offset)
      numpy.save('waterfall' + outname, masterSpectra.mean(0) )
   #print time.time()-t0
   #print masterSpectra.shape
   #print masterSpectra.shape


def main_radiotrans(argv):
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
   (cmdlnOpts, args) = cmdlnParser.parse_args(argv)
   if len(args) == 0:
      print "Must supply a path to the radio data file."
      sys.exit(1)
   # endif
   spectIntegTime = cmdlnOpts.spectIntTime/1000.0
   memLimit = forceIntValue(cmdlnOpts.memLimit, 100, 64000)*1e6
   dataUtilFrac = cmdlnOpts.dataUtilFrac
   if abs(dataUtilFrac) > 1.0 or dataUtilFrac == 0.0:
      print 'waterfall.py: WARNING => Invalid value for data utilization.  Forcing to 1.0'
      dataUtilFrac = 1.0
   # endif


   # Obtain common parameters for the data reduction and subsequent parts of the transient search.
   rawDataFramesPerBeam = 4   # Number of data frames per beam in the raw data file.
   rawDataFilePath = args[0]
   rawDataFilename = os.path.basename(os.path.splitext(rawDataFilePath)[0])
   rawDataFileSize = os.path.getsize(rawDataFilePath)
   rawDataFrameSize = drx.FrameSize
   rawDataNumFrames = int(rawDataFileSize/rawDataFrameSize)
   rawDataNumFramesPerPol = int(rawDataNumFrames/rawDataFramesPerBeam)
   rawDataSamplesPerFrame = 4096
   LFFT = rawDataSamplesPerFrame # Length of the FFT.
   DFTLength = LFFT - 1

   # Open the raw data file.
   try:
      rawDataFile = open(rawDataFilePath, 'rb')
   except:
      print rawDataFilePath,' not found'
      sys.exit(1)
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
      except ZeroDivisionError:
         print 'zero division error computing sample rate.'
         rawDataFile.close()
         sys.exit(1)
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
      print 'Could not obtain metadata for radio data file.'
      print anError
      rawDataFile.close()
      sys.exit(1)
   # endtry

   # Compute data reduction parameters.
   numDFTsPerSpectLine = max(1, int(spectIntegTime/rawDataFrameTime))
   rawDataNumSpectLines = max(1, int( rawDataNumFramesPerPol/numDFTsPerSpectLine ))
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
         commConfigObj.set('Raw Data', 'numframesperpol', rawDataNumFramesPerPol)
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
         commConfigObj.write(commConfigFile)
         commConfigFile.flush()
         commConfigFile.close()
      except:
         print 'Could not open or write common parameters file.'
         commConfigFile.close()
         sys.exit(1)
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

   # Create spectrogram tiles.
   tileIndex = numSpectLinesPerProc*procRank
   while fileOffset < endFileOffset:
      rawDataFile.seek(fileOffset, os.SEEK_CUR)
      procMessage("Integrating tile={tile} => spectrogram lines {start} to {end}...".format(start=tileIndex,
                  end=tileIndex + numSpectLinesPerProc - 1, tile=tileIndex), root=0)
      for i in lineIndices:
         procMessage("Integrating line={line} of {total} in tileIndex={tile}...".format(line=i+1, 
                     tile=tileIndex, total=numSpectLinesPerProc), root=0)
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
                  frameDFT = numpy.fft.fftshift(numpy.fft.fft(timeData)[1:])
                  # Determine the tuning of the computed DFT and add its power to the appropriate power DFT.
                  (beam, tune, pol) = currFrame.parseID()
                  if tune == 0:
                     powerDFT0 = powerDFT0 + frameDFT.real**2 + frameDFT.imag**2
                  else:
                     powerDFT1 = powerDFT1 + frameDFT.real**2 + frameDFT.imag**2
                  # endif
                  k += 1
               else:
                  k = rawDataFramesPerBeam
               # endif
            # endwhile
         # endfor
         
         # Normalize to units of energy and time average the integrated power DFTs and save them 
         # in the appropriate spectrogram tile.
         spectTile0[i,:] = powerDFT0[:]/(4*LFFT*numDFTsPerSpectLine)
         spectTile1[i,:] = powerDFT1[:]/(4*LFFT*numDFTsPerSpectLine)

         # Reset for the next integrated power DFTs.
         powerDFT0.fill(0)
         powerDFT1.fill(0)
      # endfor

      # Write tuning 0  spectrogram tile to numpy file.
      procMessage("Writing tuning 0 spectrogram tile tileIndex={tile}...".format(tile=tileIndex))
      outFilepath = createWaterfallFilepath(tile=tileIndex, tuning=0, beam=rawDataBeamID,
                                            label=cmdlnOpts.label, workDir=cmdlnOpts.workDir)
      numpy.save(outFilepath, spectTile0)
      # Write tuning 1 spectrogram tile to numpy file.
      procMessage("Writing tuning 1 spectrogram tile tileIndex={tile}...".format(tile=tileIndex))
      outFilepath = createWaterfallFilepath(tile=tileIndex, tuning=1, beam=rawDataBeamID,
                                            label=cmdlnOpts.label, workDir=cmdlnOpts.workDir)
      numpy.save(outFilepath, spectTile1)


      # Compute the fileOffset in the raw data from which we will create the next spectrogram tile for
      # this process and determine if that is past the end of the file (in which case, we stop).
      fileOffset = fileOffset + fileStep*nProcs
      tileIndex = tileIndex + numSpectLinesPerProc*nProcs
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
   procMessage("Done!")
# end main_cregg()

if __name__ == "__main__":
   #main_orig(sys.argv[1:])
   main_radiotrans(sys.argv[1:])
# endif
