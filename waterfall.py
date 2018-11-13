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
import ConfigParser
import mmap
from optparse import OptionParser
from apputils import procMessage
from apputils import Decimate



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

   LFFT = 4096 # Length of the FFT. 4096 is the size of a frame read.
   nFramesPerBeam = 4   # Number of data frames per beam in the raw data file.

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
                           help="Total memory usage limit, in MB to a maximum of 64 MB, of " + 
                                "spectrogram tiles among all processes.",
                           metavar="MB")
   (cmdlnOpts, args) = cmdlnParser.parse_args(argv)
   if len(args) == 0:
      print "Must supply a path to the radio data file."
      sys.exit(1)
   # endif
   spectIntegTime = cmdlnOpts.spectIntTime/1000.0
   memLimit = (1024**2)*min(cmdlnOpts.memLimit, 64)

   # Open the raw data file.
   try:
      rawDataFile = open(args[0], "rb")
   except:
      print args[0],' not found'
      sys.exit(1)
   # endtry

   # Obtain common parameters for the data reduction and subsequent parts of the transient search.
   rawDataFilePath = args[0]
   rawDataFilename = os.path.basename(os.path.splitext(rawDataFilePath)[0])
   rawDataFileSize = os.path.getsize(rawDataFilePath)
   rawDataFrameSize = drx.FrameSize
   rawDataNumFrames = rawDataFileSize/rawDataFrameSize
   rawDataNumFramesPerPol = rawDataNumFrames/4
   rawDataSamplesPerFrame = 4096
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
      rawDataFile.seek(-rawDataFrameSize, 1)
      rawDataTuningFreq0 = 0.0
      rawDataTuningFreq1 = 0.0
      for i in xrange(nFramesBeam):
         junkFrame = drx.readFrame(rawDataFile)
         beam,tune,pol = junkFrame.parseID()
         if pol == 0:
            if tune == 0:
                  rawDataTuningFreq0 = junkFrame.getCentralFreq()
            else:
                  rawDataTuningFreq1 = junkFrame.getCentralFreq()
            # endif
         # endif
      # endfor
      rawDataFile.seek(-nFramesPerBeam*rawDataFrameSize, 1)
   except:
      print 'Could not read radio data file for metadata.'
      rawDataFile.close()
      sys.exit(1)
   # endtry

   # Compute data reduction parameters.
   # CCY - We need to redo the distribution of spectral lines to the various processsors.  Basically,
   # the waterfall files should be much smaller and avoid having to make use of memory maps, as they are
   # cumbersome and likely prone to usage error.
   numDFTsPerSpectLine = ceil(spectIntegTime/rawDataFrameTime)
   numSpectLines = max(1, floor(rawDataNumFramesPerPol/numDFTsPerSpectLine))
   numSpectLinesPerProc = floor(memLimit/(nProcs*LFFT*numpy.dtype(numpy.float32).itemsize))
   
   # Output common parameters to the common parameters file.  NOTE: the common parameters filename is
   # currently hard-coded.  This may be changed later.
   try:
      commConfigFile = open(cmdlnOpts.configFilepath, 'w')
      commConfigObj = ConfigParser.ConfigParser()
      commConfigObj.add_section('Raw Data')
      commConfigObj.add_section('Reduced DFT Data')
      commConfigObj.set('Raw Data', 'filepath', rawDataFilePath)
      commConfigObj.set('Raw Data', 'filename', rawDataFilename)
      commConfigObj.set('Raw Data', 'filesize', rawDataFileSize)
      commConfigObj.set('Raw Data', 'framesize', rawDataFrameSize)
      commConfigObj.set('Raw Data', 'numframes', rawDataNumFrames)
      commConfigObj.set('Raw Data', 'numframesperpol', rawDataNumFramesPerPol)
      commConfigObj.set('Raw Data', 'numsamplesperframe', rawDataSamplesPerFrame)
      commConfigObj.set('Raw Data', 'samplerate', rawDataSampleRate)
      commConfigObj.set('Raw Data', 'sampletime', rawDataSampleTime)
      commConfigObj.set('Raw Data', 'frametime', rawDataFrameTime)
      commConfigObj.set('Raw Data', 'tuningfreq0', rawDataTuningFreq0)
      commConfigObj.set('Raw Data', 'tuningfreq1', rawDataTuningFreq1)
      commConfigObj.set('Raw Data', 'beam', rawDataBeamID)
      commConfigObj.set('Reduced DFT Data', 'DFTlength', LFFT)
      commConfigObj.set('Reduced DFT Data', 'integrationtime', spectIntegTime)
      commConfigObj.set('Reduced DFT Data', 'numspectrogramlines', numSpectLines)
      commConfigObj.set('Reduced DFT Data', 'numDFTsperspectrogramline', numDFTsPerSpectLine)
      commConfigObj.set('Reduced DFT Data', 'numspectrogramlinespertile', numSpectLinesPerProc)
      commConfigObj.write(commConfigFile)
      commConfigFile.close()
   except:
      print 'Could not open or write common parameters file.'
      commConfigFile.close()
      sys.exit(1)
   # endtry

   # Each process creates spectrogram tiles that are limited in size by the memory limits specified by
   # the user.  So we need to figure out how each process will step through the raw data file for each
   # spectrogram tile that it is supposed to create.
   fileStep = 4*frameSize*numDFTsPerSpect*numSpectPerProc
   fileOffset = fileStep*procRank

   # Precompute indices for the spectrogram tile and counting the raw DFTs.
   lineIndices = range(numSpectLinesPerProc)
   dftIndices = range(numDFTsPerSpectLine)

   # Build the working arrays for the computing DFTs, integrating the DFTs into a power spectrum, and
   # composing a single spectrogram tile.
   DFTX0 = numpy.zeros(LFFT, dtype=numpy.complex_)
   DFTY0 = numpy.zeros(LFFT, dtype=numpy.complex_)
   DFTX1 = numpy.zeros(LFFT, dtype=numpy.complex_)
   DFTY1 = numpy.zeros(LFFT, dtype=numpy.complex_)
   powerDFT0 = numpy.zeros(LFFT, dtype=numpy.complex_)
   powerDFT1 = numpy.zeros(LFFT, dtype=numpy.complex_)
   spectTile0 = numpy.ndarray(shape=(numSpectLinesPerProc, LFFT), dtype=numpy.float32)
   spectTile1 = numpy.ndarray(shape=(numSpectLinesPerProc, LFFT), dtype=numpy.float32)

   # Create spectrogram tiles.
   tileIndex = numSpectLinesPerProc*procRank
   while fileOffset < rawDataFileSize:
      dataFile.seek(fileOffset)
      for i in lineIndices:
         for j in dftIndices:
            # Read 4 frames from the raw data and compute their DFTs.
            for k in range(4):
               # Compute the DFT of the current frame.
               currFrame = drx.readFrame(rawDataFile) 
               frameDFT = numpy.fft.fftshift(numpy.fft.fft2(currFrame.data.iq))
               # Determine the tuning and polarization of the computed DFT.
               (beam, tune, pol) = currFrame.parseID()
               if tune = 0:
                  if pol = 0:
                     DFTX0 = frameDFT
                  else
                     DFTY0 = frameDFT
                  # endif
               else
                  if pol = 0:
                     DFTX1 = frameDFT
                  else:
                     DFTY1 = frameDFT
                  # endif
               # endif
            # endfor
            # Integrate the Stokes parameter power DFTs for each tuning
            powerDFT0 = powerDFT0 + (DFTX0.real**2 + DFTX0.imag**2 + DFTY0.real**2 + DFTY0.imag**2)
            powerDFT1 = powerDFT1 + (DFTX1.real**2 + DFTX1.imag**2 + DFTY1.real**2 + DFTY1.imag**2)
         # endfor
         
         # Normalize the integrated power DFTs to units of energy and save them in the appropriate
         # spectrogram tile.
         spectTile0[i,:] = powerDFT0[:]/(4*LFFT)
         spectTile1[i,:] = powerDFT1[:]/(4*LFFT)

         # Reset for the next integrated power DFTs.
         powerDFT0.fill(0)
         powerDFT1.fill(0)
      # endfor

      # Write tuning 0  spectrogram tile to numpy file.
      outFilename = "{dir}/waterfall-S{tile}T{tune}".format(dataname=rawDataFilename, tile=tileIndex, 
                                                            tune=0, dir=cmdlnOpts.workDir)
      numpy.save(outFilename, spectTile0)
      # Write tuning 1 spectrogram tile to numpy file.
      outFilename = "{dir}/waterfall-S{tile}T{tune}".format(dataname=rawDataFilename, tile=tileIndex, 
                                                            tune=1, dir=cmdlnOpts.workDir)
      numpy.save(outFilename, spectTile1)


      # Compute the fileOffset in the raw data from which we will create the next spectrogram tile for
      # this process and determine if that is past the end of the file (in which case, we stop).
      fileOffset = fileOffset + fileStep*nProcs
      tileIndex = tileIndex + numSpectLinesPerProc*nProcs
      if fileOffset < rawDataFileSize:
         # Compute how much remains of the raw data file and determine whether there is enough to create
         # a full spectrogram tile or whether we need to create a smaller tile.
         fileRemain = fileOffset + 1 - rawDataFileSize
         if fileRemain < fileStep:
            numFramesRemain = fileRemain/rawDataFrameSize
            numDFTsRemain = numFramesRemain/4
            numSpectLinesPerProc = floor(numDFTsRemain/numDFTsPerSpectLine)
            # Resize the spectrogram tile arrays to the new, smaller size.
            spectTile0.resize((numSpectLinesPerProc, LFFT))
            spectTile1.resize((numSpectLinesPerProc, LFFT))
         # endif
      # endif
   # endwhile
# end main_cregg()

if __name__ == "__main__":
   #main_orig(sys.argv[1:])
   main_radiotrans(sys.argv[1:])
# endif
