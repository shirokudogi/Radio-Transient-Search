import os
import sys
import numpy
import getopt
import drx
import errors
from optparse import OptionParser
from apputils import forceIntValue

def main_orig(args):
	windownumber = 4

	#Low tuning frequency range
	Lfcl = 2700 * windownumber
	Lfch = 2800 * windownumber
	#High tuning frequency range
	Hfcl = 1500 * windownumber
	Hfch = 1600 * windownumber

	nChunks = 3000 #the temporal shape of a file.
	LFFT = 4096 * windownumber #Length of the FFT.4096 is the size of a frame readed.
	nFramesAvg = 1 * 4 * windownumber # the intergration time under LFFT, 4 = beampols = 2X + 2Y (high and low tunes)

	#for offset_i in range(4306, 4309):# one offset = nChunks*nFramesAvg skiped
	for offset_i in range(0, 1):# one offset = nChunks*nFramesAvg skiped
		offset = 0
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
		print 'Low  freq  = ', freq1[Lfcl],freq1[Lfch],' at', freq1[Lfcl]/2+freq1[Lfch]/2
		print 'High freq  = ', freq2[Hfcl],freq2[Hfch],' at', freq2[Hfcl]/2+freq2[Hfch]/2
		numpy.save('tInt',tInt)
		numpy.save('freq1',freq1[Lfcl:Lfch])
		numpy.save('freq2',freq2[Hfcl:Hfch])
# end main_orig()
#


def main_radiotrans(args):
   LFFT = 4096 # Length of the FFT. 4096 is the size of a frame read.

   # Setup the command-line options.
   usage="USAGE: %prog [options] <radio data filepath>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option("-l0","--tune0-fftlow",dest="tune0FCL", default=0, type="int",
                           action="store",
                           help="Lower FFT index (between 0 and 4095) for tuning 0.", 
                           metavar="INDEX")
   cmdlnParser.add_option("-h0","--tune0-ffthigh",dest="tune0FCH", default=4095, type="int",
                           action="store",
                           help="Upper FFT index (between 0 and 4095) for tuning 0.", 
                           metavar="INDEX")
   cmdlnParser.add_option("-l1","--tune1-fftlow",dest="tune1FCH", default=0, type="int",
                           action="store",
                           help="Lower FFT index (between 0 and 4095) for tuning 1.", 
                           metavar="INDEX")
   cmdlnParser.add_option("-h1","--tune1-ffthigh",dest="tune1FCH", default=4095, type="int",
                           action="store",
                           help="Upper FFT (between 0 and 4095) index for tuning 1.", 
                           metavar="INDEX")
   cmdlnParser.add_option("-w", "--work-dir", dest="workDir", default=".",
                          action="store",
                          help="Working directory path.", metavar="PATH")
   cmdlnParser.add_option('-c', '--commconfig', dest='configFilepath', default='./radiotrans.ini',
                           type='string', action='store',
                           help='Path to the common parameters file.', metavar='PATH')
   
   # Parse command-line for FFT indices and the radio data file path.
   (cmdlnOpts, cmdlnParams) = cmdlnParser.parse_args()
   tune0FCL = forceIntValue(cmdlnOpts.tune0FCL, 0, 4095)
   tune0FCH = forceIntValue(cmdlnOpts.tune0FCH, 0, 4095)
   tune1FCH = forceIntValue(cmdlnOpts.tune1FCH, 0, 4095)
   tune1FCH = forceIntValue(cmdlnOpts.tune1FCH, 0, 4095)
   if len(cmdlnArgs) > 0:
      rawDataPath = cmdlnParams[0]
   else:
      print 'Must provide the path to the raw radio data file.'
      sys.exit(1)
   # endif

   # Validate command-line inputs.
   if tune0FCH <= tune0FCL:
      print('ERROR: Tuning 0 lower FFT index must be less than the upper FFT index')
      exit(1)
   # endif
   if tune1FCH <= tune1FCH:
      print('ERROR: Tuning 1 lower FFT index must be less than the upper FFT index')
      exit(1)
   # endif
   if len(rawDataPath) == 0:
      print('Path to the original data file must be provided')
      exit(1)
   # end if
   
   # Update the common parameters file with the bandpass limits.
   try:
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj = ConfigParser.ConfigParser()
      commConfigObj.readfp(configFile, cmdlnOpts.configFilepath)
      configFile.close()

      configFile = open(cmdlnOpts.configFilepath,"w")
      commConfigObj.add_section('Bandpass')
      commConfigObj.set('Bandpass', 'tune0_lowFFT', tune0FCL)
      commConfigObj.set('Bandpass', 'tune0_highFFT', tune0FCH)
      commConfigObj.set('Bandpass', 'tune1_lowFFT', tune1FCH)
      commConfigObj.set('Bandpass', 'tune1_highFFT', tune1FCH)
      commConfigObj.write(commConfigFile)
      configFile.close()
   except:
      print 'Could not update common parameters file: {file}'.format(file=cmdlnOpts.configFilepath)
      sys.exit(1)
   # endtry

   # Open the radio data file.
   try:
      inFilename = os.path.basename(os.path.splitext(rawDataPath)[0])
      inFile = open(rawDataPath, "rb")
      nFramesFile = os.path.getsize(rawDataPath) / drx.FrameSize #drx.FrameSize = 4128
   except:
      print rawDataPath,' not found'
      sys.exit(1)
   # endtry

   try:
      junkFrame = drx.readFrame(inFile)
      try:
         srate = junkFrame.getSampleRate()
         pass
      except ZeroDivisionError:
         print 'zero division error computing sampling rate.'
         inFile.close()
         exit(1)
      # endtry
   except errors.syncError:
      print 'assuming the srate is 19.6 MHz'
      inFile.seek(-drx.FrameSize+1, 1)
   # endtry

   # Extract metadata for the radio data file using the first 4 frames.
   # CCY - NOTE: There is an implicit assumption that a given radio data file is associated with only a
   # single beam.
   #
   beam,tune,pol = junkFrame.parseID()
   beams = drx.getBeamCount(inFile)
   tunepols = drx.getFramesPerObs(inFile)
   tunepol = tunepols[0] + tunepols[1] + tunepols[2] + tunepols[3]
   beampols = tunepol

   # Use the first 4 frames to determing the high and low tuning frequencies
   #
   inFile.seek(-drx.FrameSize, 1)
   centralFreq1 = 0.0
   centralFreq2 = 0.0
   for i in xrange(4):
      junkFrame = drx.readFrame(inFile)
      b,t,p = junkFrame.parseID()
      if p == 0:
         if t == 0:
            try:
               centralFreq1 = junkFrame.getCentralFreq()
            except AttributeError:
               from dp import fS
               centralFreq1 = fS * ((junkFrame.data.flags[0]>>32) & (2**32-1)) / 2**32
         else:
            try:
               centralFreq2 = junkFrame.getCentralFreq()
            except AttributeError:
               from dp import fS
               centralFreq2 = fS * ((junkFrame.data.flags[0]>>32) & (2**32-1)) / 2**32
         # endif
      # endif
   # end for i in xrange(4)

   # Determine the set of frequencies on the FFT for both tunings and the temporal resolution.  Save
   # this information to disk.
   freq = numpy.fft.fftshift(numpy.fft.fftfreq(LFFT, d = 1.0/srate))
   tInt = 1.0*LFFT/srate
   print 'Temporal resl = {time} secs'.format(time=tInt)
   print 'Channel width = {freq} Hz'.format(freq=1.0/tInt)
   freq1 = freq+centralFreq1
   freq2 = freq+centralFreq2
   print 'Low freq bandpass = {low} - {high} Hz at tuning {tuning} Hz'.format(low=freq1[tune0FCL],
         high=freq1[tune0FCH],tuning=centralFreq1)
   print 'High freq bandpass = {low} - {high} Hz at tuning {tuning} Hz'.format(low=freq2[tune1FCH],
         high=freq2[tune1FCH],tuning=centralFreq2)
   numpy.save('{dir}/tInt'.format(dir=cmdlnOpts.workDir), tInt)
   numpy.save('{dir}/lowtunefreq'.format(dir=cmdlnOpts.workDir), freq1)
   numpy.save('{dir}/hightunefreq'.format(dir=cmdlnOpts.workDir), freq2)

   inFile.close()
# end main()
#
if __name__ == "__main__":
   # main_orig(sys.argv[1:])
   main_radiotrans(sys.argv[1:])
# endif

