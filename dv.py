import sys
import os
import time
import sys
import tempfile
import mmap
import numpy as np
from mpi4py import MPI
from optparse import OptionParser
from ConfigParser import ConfigParser
import apputils


class PulseSignal():
   formatter = "{0.pulse:10s}    {0.SNR:10.6f}    {0.DM:10.4f}    {0.time:10.6f} " + \
               "    {0.dtau:10.6f}    {0.dnu:.4f}    {0.nu:.4f}    {0.mean:.5f}" + \
               "    {0.rms:0.5f}    {0.nu1:.4f}    {0.nu2:.4f}\n " 

   def __init__(self):
      self.pulse = None    # Pulse Number
      self.SNR   = None    # SNR of pulse
      self.DM    = None    # DM (pc/cm3) of pulse
      self.time  = None    # Time at which pulse ocurred
      self.dtau  = None    # Pulse-width
      self.dnu   = None    # Spectral resolution
      self.nu    = None    # Central Observing Frequency
      self.mean  = None    # Noise floor mean in the time series
      self.rms   = None    # Noise floor RMS in the time series
      self.nu1   = None    # Bottom frequency in the bandpass
      self.nu2   = None    # Top frequency in the bandpass
   # end __init__()

   def __str__(self):
      return PulseSignal.formatter.format(self)
   # end __str__()

   def field_names(self):
      return  "{0:10s}    {1:10s}    {2:10s}    {3:10s} " + \
              "    {4:10s}    {5:5s}    {6:6s}    {7:7s}" + \
              "    {8:5s}    {9:6s}    {10:6s}\n ".format("pulse_ID", "snr", "DM", "time",
                                                          "width", "dnu", "cfreq", "mean",
                                                          "rms", "nu1", "nu2")
   # end field_names()
   
# end class PulseSignal


def Threshold(ts, thresh, clip=3, niter=1):
   """
   Wrapper to scipy threshold a given time series using Scipy's threshold function (in 
   scipy.stats.stats).  First it calculates the mean and rms of the given time series.  It then 
   makes the time series in terms of SNR.  If a given SNR value is less than the threshold, it is 
   set to "-1".  Returns a SNR array with values less than thresh = -1, all other values = SNR.
   Also returns the mean and rms of the timeseries.
   Required:
   ts   -  input time series.
   Options:
   thresh  -  Time series signal-to-noise ratio threshold.  default = 5.
   clip    -  Clipping SNR threshold for values to leave out of a mean/rms calculation.  default = 3.
   niter   -  Number of iterations in mean/rms calculation.  default = 1.
   Usage:
   >>sn, mean, rms = Threshold(ts, *options*)
   """
   #  Calculate, robustly, the mean and rms of the time series.  Any values greater than 3sigma are left
   #  out of the calculation.  This keeps the mean and rms free from sturation due to large deviations.

   mean = np.mean(ts) 
   std  = np.max([np.std(ts), apputils.epsilon]) # Need to keep std from being exactly zero.

   if niter > 0:
      for i in range(niter):
         mask = ((ts-mean)/std < clip)  # only keep the values less than 3sigma
         mean = np.mean(ts[mask])
         std  = np.max([np.std(ts[mask]), apputils.epsilon])
      # endfor
   # endif

   SNR = (ts - mean)/std
   SNR[SNR < thresh] = -1

   return (SNR, mean, std)
# end Threshold()


def main_routine(args):
   # Get the MPI environment.
   MPIComm  = MPI.COMM_WORLD
   numProcs = MPIComm.Get_size()
   rank  = MPIComm.Get_rank()

   # Create an empty radio pulse.  This will be filled in later and written to the output file.
   pulse = PulseSignal() 

   # Setup the commandline.
   usage = " Usage: %prog [options] <radio filepath>"
   cmdlnParser = OptionParser(usage=usage)
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
   cmdlnParser.add_option("-o", "--output-file", dest="outFilepath", type="string", 
                           default="./transients.txt", action="store",
                           help="Path to the output file of transient events.",
                           metavar="PATH")
   cmdlnParser.add_option("-p", "--max-pulse-width", dest="maxPulseWidth", type="float", 
                           default=1, action="store",
                           help="Maximum pulse width to search in seconds. default = 1 sec.",
                           metavar="SECS")
   cmdlnParser.add_option("-t", "--snr-threshold", dest="SNRThreshold", type="float", 
                           default=5.0, action="store",
                           help="SNR lower bound cut off threshold.",
                           metavar="SNR")
   cmdlnParser.add_option("--tuning1", dest="enableTuning1", default=False, action="store_true",
                           help="Flag denoting whether this is tuning 0 (disabled) or tuning 1 (enabled).")
   cmdlnParser.add_option("-s", "--dm-start", dest="DMStart", type="float", default=None, action="store",
                           help="Starting dispersion measure value.",
                           metavar="DM")
   cmdlnParser.add_option("-e", "--dm-end", dest="DMEnd", type="float", default=1000.0, action="store",
                           help="Ending dispersion measure value.",
                           metavar="DM")
   cmdlnParser.add_option("--dm-step", dest="DMStep", type=float, default=1.0, action="store",
                           help="Interval step-size for dispersion measure search.",
                           metavar="STEP")
   # Parse the commandline.                           
   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)

   # Get the spectrogram filepath from the arguments. We just take the first argument.
   if len(cmdlnArgs) > 0:
      spectFilepath = cmdlnArgs[0]
   else:
      apputils.procMessage("dv.py: Path to spectrogram file must be specified.", msg_type="ERROR")
      sys.exit(1)
   # endif

   # Obtain bandpass and integration parameters from the common parameters file.
   try:
      # Read the common parameters file.
      commConfigFile = open(cmdlnOpts.configFilepath, 'r')
      commConfigObj = ConfigParser()
      commConfigObj.readfp(commConfigFile, cmdlnOpts.configFilepath)
      commConfigFile.close()
      
      # Parse DFT length and integration time, in seconds.
      DFTLength = commConfigObj.getint("Reduced DFT Data", "dftlength")
      tInt = commConfigObj.getfloat("Reduced DFT Data", "integrationtime")
      # Parse bandwidth and center frequency.
      bandwidth = commConfigObj.getfloat("Raw Data","samplerate")/10**6
      lowerFFTIndex = 0
      upperFFTIndex = DFTLength - 1
      if not cmdlnOpts.enableTuning1:
         centerFreq = commConfigObj.getfloat("Raw Data", "tuningfreq0")/10**6
         if commConfigObj.has_section("RFI Bandpass"):
            lowerFFTIndex = commConfigObj.getint("RFI Bandpass", "lowerfftindex0")
            upperFFTIndex = commConfigObj.getint("RFI Bandpass", "upperfftindex0")
         # endif
      else:
         centerFreq = commConfigObj.getfloat("Raw Data", "tuningfreq1")/10**6
         if commConfigObj.has_section("RFI Bandpass"):
            lowerFFTIndex = commConfigObj.getint("RFI Bandpass", "lowerfftindex1")
            upperFFTIndex = commConfigObj.getint("RFI Bandpass", "upperfftindex1")
         # endif
      # endif

      # Compute channel width, with the caveat that the DC component of the DFT was removed during the
      # data reduction.
      channelWidth = bandwidth/(DFTLength)
   except:
      apputils.procMessage("dv.py: Could not open or read common parameters file {file}".format(
                  file=cmdlnOpts.configFilepath), msg_type="ERROR")
      sys.exit(1)
   # endtry
   
   # Load the spectrogram file and determine partitioning to each process..
   segmentSize = None
   segmentOffset = None
   spectrogram = None
   numSpectLines = 0
   bandpassLength = None
   if rank == 0:
      # Load spectrogram.
      apputils.procMessage('dv.py: Loading spectrogram (may take a while)', root=0)
      try:
         spectrogram = np.load(spectFilepath, mmap_mode='r')
      except:
         apputils.procMessage("dv.py: Could not open or load spectrogram file {file}".format(
                              file=spectFilepath), msg_type="ERROR", root=0)
         sys.exit(1)
      # endtry
      numSpectLines = spectrogram.shape[0]
      bandpassLength = spectrogram.shape[1]

      # Determine partitioning of spectrogram to each processes.
      segmentSize = np.zeros(numProcs, dtype=np.int64)
      segmentOffset = np.zeros(numProcs, dtype=np.int64)
      segmentSize[1:] = np.int64( numSpectLines/numProcs )
      segmentSize[0] = np.int64( numSpectLines - (numProcs - 1)*segmentSize[1] )
      segmentOffset[0] = 0
      segmentOffset[1:] = segmentSize[0] + segmentSize[1]*np.arange(numProcs - 1, dtype=np.int64)
   # endif
   # Distribute spectrogram partitions to processes.
   apputils.procMessage('dv.py: Distributing spectrogram segments', root=0)
   numSpectLines = MPIComm.bcast(numSpectLines, root=0)
   bandpassLength = MPIComm.bcast(bandpassLength, root=0)
   segmentSize = MPIComm.bcast(segmentSize, root=0)
   segmentOffset = MPIComm.bcast(segmentOffset, root=0)
   segment = np.zeros(shape=(segmentSize[rank], bandpassLength), dtype=np.float32)
   MPIComm.Scatterv([spectrogram, segmentSize*bandpassLength, segmentOffset*bandpassLength, MPI.FLOAT], 
                    [segment, segmentSize[rank]*bandpassLength, MPI.FLOAT],
                    root=0)

   # Open the shared output file.
   try:
      outFile = MPI.File.Open(MPIComm, cmdlnOpts.outFilepath, MPI.MODE_WRONLY | MPI.MODE_CREATE)
   except:
      apputils.procMessage("dv.py: Could not open/create output file {file}".format(
                           file=cmdlnOpts.outFilepath), msg_type="ERROR")
   # endtry

   # Extract commandline parameters.
   thresh= cmdlnOpts.SNRThreshold
   DMstart = cmdlnOpts.DMStart
   DMend = cmdlnOpts.DMEnd
   DMstep = cmdlnOpts.DMStep

   # Compute the set of frequencies in the bandpass to de-disperse.  The topmost frequency is the top
   # frequency of the bandpass, which is pinned in placed for the de-dispersion.  The frequencies below
   # that are the frequencies at the center of each frequency channel.
   chFreqs = apputils.computeFreqs(centerFreq, bandwidth, lowerFFTIndex,
                                 upperFFTIndex, DFTLength)
   bottomFreqBP = chFreqs[0]    # Bottom frequency in the bandpass.
   topFreqBP = chFreqs[-1] + channelWidth   # Top frequency in the bandpass.
   numChannels = len(chFreqs)
   # Compute dispersed frequencies.
   freqs = np.zeros(numChannels + 1, dtype=np.float32)
   freqs[0:numChannels] = freqs[0:numChannels] + 0.5*channelWidth
   freqs[-1] = topFreqBP
   # Create list of indices for the dispersed channels.
   freqIndices = np.arange(numFreqs, dtype=np.int32)

   # Setup pulse search parameters and add the maximum pulse-width to the common parameters file..
   log2MaxPulseWidth = np.round( np.log2(cmdlnOpts.maxPulseWidth/tInt) ).astype(np.int32) + 1 
   pulseID = 0

   # Determine dispersion measure trials and scaled dispersion delays.
   DMtrials = np.arange(cmdlnParser.DMStart, cmdlnParser.DMEnd, cmdlnParser.DMStep, dtype=np.float32)
   scaledDelays = apputils.scaleDelays(freqs)/tInt

   # Allocate the de-dispersed time series. Yes, this is allocating the worst case, which results in
   # some wasted space, but it should run much faster without having to perform an allocation for each
   # DM trial.  Also, the time series occupy far, far less space than the spectrogram.
   tbMax = np.floor(cmdlnOpts.DMEnd*scaledDelays[0]).astype(np.int32)
   ts = np.zeros(tbMax + numSpectLines, dtype=np.float32)
   tstotal = np.zeros(ts.shape[0], dtype=np.float32)


   # Write additional parameter information into the common parameters file.
   MPIComm.Barrier() # To ensure all processes have had a chance to read the common parameters file
                     # before update.
   if rank == 0:
      try:
         commConfigFile = open(cmdlnOpts.configFilepath, 'w')
         if not commConfigObj.has_section("De-disperse Search"):
            commConfigObj.add_section("De-disperse Search")
         # endif
         commConfigObj.set("De-disperse Search", "dmstart", cmdlnOpts.DMStart)
         commConfigObj.set("De-disperse Search", "dmend", cmdlnOpts.DMEnd)
         commConfigObj.set("De-disperse Search", "dmstep", cmdlnOpts.DMStep)
         commConfigObj.set("De-disperse Search", "maxpulsewidth", cmdlnOpts.maxPulseWidth)
         commConfigObj.write(commConfigFile)
         commConfigFile.close()
      except Exception as anErr:
         print anErr
         apputils.procMessage('dv.py: Could not open or write common parameters file ' +
                              '{file}'.format(file=cmdlnOpts.configFilepath), root=0,
                              msg_type='ERROR')
         sys.exit(1)
      # endtry
   # endif

   # Synchronize processes to ensure they are all on the same dispersion measure trial.
   MPIComm.Barrier()

   # Perform de-dispersion search for pulses with temporal widths less than or equal to the specified 
   # pulse-width.
   for DM in DMtrials:
      apputils.procMessage("dv.py: De-dispersion with DM = {dm}".format(dm=DM), root=0)
      # Compute array of dispersion delays as an index in units of tInt.
      tShifts = np.floor(DM*scaledDelays).astype(np.int32)
      fShifts = tShifts[0] - tShifts
      # De-disperse the frequencies assigned to this process.
      for fIndex in freqIndices: 
         beginIndex = segmentOffset[rank] + fShifts[fIndex]
         endIndex = beginIndex + segmentSize[rank]
         ts[beginIndex : endIndex] += segment[ : , fIndex]
      # endfor

      # Merge the de-dispersed time-series from all processes.
      MPIComm.Allreduce(ts, tstotal, op=MPI.SUM)

      # Search for signal with decimated timeseries
      if rank < log2MaxPulseWidth:
         apputils.procMessage("dv.py: Searching for pulses".format(dm=DM))

         # Cut the dispersed time lag.
         ndown = 2**rank #decimate the time series
         dedispTS = apputils.DecimateNPY(tstotal[tShifts[0] : numSpectLines], ndown)
         if len(dedispTS) != 0:
            (snr, mean, rms) =  Threshold(dedispTS, thresh, niter=0)
            pulseIndices = np.where(snr != -1)[0]
            if len(pulseIndices) > 0:
               apputils.procMessage( "dv.py: {num} pulses found.  Writing to file.".format(
                                    num=len(pulseIndices)) )
               for index in pulseIndices:# Now record all pulses above threshold
                  pulse.pulse = "{idnum}_{rank}".format(rank=rank, idnum=pulseID)
                  pulse.SNR = snr[index]
                  pulse.DM = DM
                  pulse.time = (index + 0.5)*tInt*ndown
                  pulse.dtau = tInt*ndown
                  pulse.dnu = channelWidth
                  pulse.nu = centerFreq
                  pulse.mean = mean
                  pulse.rms = rms
                  pulse.nu1 = bottomFreqBP
                  pulse.nu2 = topFreqBP
                  outFile.Write_shared(pulse.__str__()[:]) 

                  pulseID += 1
               # endfor
            # endif
         # endif
      # endif

      # Clear the time-series.
      tstotal.fill(0)
      ts.fill(0)

      # Synchronize processes to ensure they are all on the same dispersion measure trial.
      MPIComm.Barrier()
   # endfor

   outFile.Close()
# end main()


if __name__ == "__main__":
   main_routine(sys.argv[1:])
   sys.exit(0)
# endif
