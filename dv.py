from mpi4py import MPI
import disper
import sys
import numpy as np
import glob
import os
import time
import sys
import apputils


class PulseSignal():
   formatter = "{0.pulse:08d}    {0.SNR:10.6f}     {0.DM:10.4f}     {0.time:10.6f} " + \
               "     {0.dtau:10.6f}     {0.dnu:.4f}     {0.nu:.4f}    {0.mean:.5f}" + \
               "    {0.rms:0.5f}     {0.nu1:.4f}    {0.nu2:.4f}\n " 

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
   std  = np.std(ts)  

   if niter > 0:
      for i in range(niter):
         mask = ((ts-mean)/std < clip)  # only keep the values less than 3sigma
         mean = np.mean(ts[mask])
         std  = np.std(ts[mask])
      # endfor
   # endif

   SNR = (ts - mean)/std
   SNR[SNR < thresh] = -1

   return (SNR, mean, std)
# end Threshold()


main(args):
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
   cmdlnParser.add_option("--tuning1", dest="enableTune1", default=False, action="store_true",
                           help="Flag denoting whether this is tuning 0 (disabled) or tuning 1 (enabled).")
   cmdlnParser.add_option("-s", "--dm-start", dest="DMStart", type="string", default=None, action="store",
                           help="Starting dispersion measure value.",
                           metavar="DM")
   cmdlnParser.add_option("-e", "--dm-end", dest="DMEnd", type="float", default=1000.0, action="store",
                           help="Ending dispersion measure value.",
                           metavar="DM")
   # Parse the commandline.                           
   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)

   # Get the spectrogram filepath from the arguments. We just take the first argument.
   if len(cmdlnArgs) > 0:
      spectFilepath = cmdlnArgs[0]
   else:
      procMessage("dv.py: Path to spectrogram file must be specified.", msg_type="ERROR")
      sys.exit(1)
   # endif

   # Obtain bandpass and integration parameters from the common parameters file.
   try:
      # Read the common parameters file.
      commConfigFile = open(cmdlnOpts.configFilepath, 'r')
      commConfigObj = ConfigParser()
      commConfigObj.readfp(commConfigFile, cmdlnOpts.configFilepath)
      commConfigFile.close()
      
      # Parse bandwidth and center frequency.
      bandWidth = commConfigObj.getfloat("Raw Data","samplerate")/10^6
      if not cmdlnOpts.enableTuning1:
         centerFreq = commConfigObj.getfloat("Raw Data", "tuningfreq0")/10^6
         lowerFFTIndex = commConfigObj.getint("RFI Bandpass", "lowerfftindex0")
         upperFFTIndex = commConfigObj.getint("RFI Bandpass", "upperfftindex0")
      else:
         centerFreq = commConfigObj.getfloat("Raw Data", "tuningfreq1")/10^6
         lowerFFTIndex = commConfigObj.getint("RFI Bandpass", "lowerfftindex1")
         upperFFTIndex = commConfigObj.getint("RFI Bandpass", "upperfftindex1")
      # endif
      # Parse DFT length and integration time, in seconds.
      DFTLength = commConfigObj.getint("Reduced DFT Data", "dftlength")
      tInt = commConfigObj.getfloat("Reduced DFT Data", "integrationtime")

      # Compute channel width, with the caveat that the DC component of the DFT was removed during the
      # data reduction.
      channelWidth = bandwidth/(DFTLength + 1)
   except:
      procMessage("dv.py: Could not open or read common parameters file {file}".format(
                  file=cmdlnOpts.configFilepath), msg_type="ERROR")
      sys.exit(1)
   # endtry
   
   # Load the spectrogram file and determine the partition to each process..
   segmentSize = None
   spectrogram = None
   numSpectLines = None
   bandpassLength = None
   tsOffset = None
   if rank == 0:
      # Load spectrogram.
      try:
         spectrogram = np.load(spectFilepath, mmap_mode='r')
         numSpectLines = spectrogram.shape[0]
         bandpassLength = spectrogram.shape[1]
      except:
         procMessage("dv.py: Could not open or load spectrogram file {file}".format(file=spectFilepath),
                     msg_type="ERROR", root=0)
      # endtry

      # Determine partitioning of spectrogram to each processes.
      spectSegmentSize = np.zeros(nProcs, dtype=np.int32)
      segmentSize = np.int(numSpectLines/nProcs)
      rank0SegmentSize = numSpectLines - (nProcs - 1)*segmentSize

      # Determine time-series offsets for each spectrogram segment
      tsOffset = np.zeros(nProcs, dtype=np.int32)
      tsOffset[0] = 0
      tsOffset[1:] = rank0SegmentSize + segmentSize*np.arange(nProcs - 1)
   # endif

   # Distribute total spectrogram size information.
   numSpectLines = MPIComm.bcast(numSpectLines, root=0)
   bandpassLength = MPIComm.bcast(bandpassLength, root=0)
   # Distribute spectrogram segment sizes and alignment information.
   if rank != 0:
      segmentSize = MPIComm.bcast(segmentSize, root=0)
   else:
      segmentSize = rank0SegmentSize
   # endif
   tsOffset = MPIComm.bcast(tsOffset, root=0)
   # Distribute spectrogram segments.
   # CCY - Future upgrade: have check to see if making nProcs/numNodes spectrogram segments will exceed
   # the memory limits.  If it does, then create the spectrogram segments as memory=mapped files.
   spectSegment = np.zeros(segmentSize*bandpassLength, 
                           dtype=np.float32).reshape((segmentSize, bandpassLength))
   MPIComm.Scatterv([spectrogram, numSpectLines*bandpassLength, MPI.FLOAT], 
                    [spectSegment, segmentSize*bandpassLength, MPI.FLOAT],
                    root=0)
   
   # Open the shared output file.
   try:
      outFile = MPI.File.Open(MPIComm, cmdlnOpts.outFilepath, MPI.MODE_WRONLY | MPI.MODE_CREATE)
   except:
      procMessage("dv.py: Could not open/create output file {file}".format(file=cmdlnOpts.outFilepath),
                  msg_type="ERROR")
   # endtry

   # Extract commandline parameters.
   thresh= cmdlnOpts.SNRThreshold
   DMstart = cmdlnOpts.DMStart
   DMend = cmdlnOpts.DMEnd

   # Compute the set of frequencies in the bandpass to de-disperse.  These are the frequencies at the
   # top of the frequency bins.
   freqs = apputils.computeFreqs(centerFreq, bandwidth, lowerFFTIndex,
                                 upperFFTIndex, DFTLength + 1) + channelWidth
   freqIndices = np.arange(len(freqs), dtype=np.int32)
   bottomFreqBP = freqs[0] - channelWidth # Bottom frequency in the bandpass.

   # Setup pulse search parameters and add the maximum pulse-width to the common parameters file..
   log2MaxPulseWidth = np.round( np.log2(cmdlnOpts.maxPulseWidth/tInt) ).astype(np.int32) + 1 
   pulseID = 0

   # Determine dispersion measure trials and scaled dispersion delays.
   DMtrials = None
   scaledDelays = None
   if rank == 0:
      numMidTrials = np.floor(cmdlnOpts.DMEnd) - np.ceil(cmdlnOpts.DMStart)
      DMtrials = np.zeros(numMidTrials + 2, dtype=np.float32)
      DMtrials[0] = cmdlnOpts.DMStart
      DMtrials[numMidTrials + 1] = cmdlnOpts.DMEnd
      DMtrials[1:numTrials + 1] = np.arange(numMidTrials, dtype=np.float32) + np.ceil(cmdlnOpts.DMStart)

      scaledDelays = apputils.scaleDelays(freqs)
   # endif
   # Distribute dispersion measure trials and scaled dispersion delays.
   DMtrials = MPIComm.bcast(DMtrials, root=0)
   scaledDelays = MPIComm.bcast(scaledDelays, root=0)

   # Allocate the de-dispersed time series. Yes, this is allocating the worst case, which results in
   # some wasted space, but it should run much faster without having to perform an allocation for each
   # DM trial.  Also, the time series occupy far, far less space than the spectrogram.
   tbMax = np.round(cmdlnOpts.DMEnd/tInt*scaledDelays[0]).astype(np.int32)
   ts = np.zeros(tbMax + numSpectLines, dtype=np.float32)
   tstotal = np.zeros(ts.shape[0], dtype=np.float32)


   # Write additional parameter information into the common parameters file.
   if rank == 0:
      try:
         commConfigFile = open(cmdlnOpts.configFilepath, 'w')
         commConfigObj.add_section("De-disperse Search")
         commConfigObj.set("De-disperse Search", "dmstart", cmdlnOpts.DMStart)
         commConfigObj.set("De-disperse Search", "dmend", cmdlnOpts.DMEnd)
         commConfigObj.set("De-disperse Search", "maxpulsewidth", maxPulseWidth)
         commConfigObj.write(commConfigFile)
         commConfigFile.close()
      except:
      # endtry
   # endif

   # Synchronize processes to ensure they are all on the same dispersion measure trial.
   MPIComm.Barrier()

   # Perform de-dispersion search for pulses with temporal widths less than or equal to the specified 
   # pulse-width.
   for DM in DMtrials:
      procMessage("dv.py: De-dispersion with DM = {dm}".format(dm=DM), root=0)
      # Compute array of dispersion delays as an index in units of tInt.
      tb=np.round(DM/tInt*scaledDelays).astype(np.int32)
      fShifts = tb[0] - tb
      # De-disperse the frequencies assigned to this process.
      for fIndex in freqIndices: 
         beginIndex = tsOffset[rank] + fShifts[fIndex]
         endIndex = beginIndex + segmentSize
         ts[beginIndex : endIndex] += spectSegment[ : , fIndex]
      # endfor

      # Merge the de-dispersed time-series from all processes.
      MPIComm.Allreduce(ts, tstotal, op=MPI.SUM)

      # Search for signal with decimated timeseries
      if rank < log2MaxPulseWidth:
         procMessage("dv.py: Searching for pulses".format(dm=DM), root=0)

         # Cut the dispersed time lag.
         dedispTS = tstotal[tb[0] : numSpectLines]
         ndown = 2**rank #decimate the time series
         (snr, mean, rms) = Threshold(apputils.DecimateNPY(dedispTS, ndown), thresh, niter=0)
         pulseIndices = np.where(sn!=-1)[0]
         for index in pulseIndices:# Now record all pulses above threshold
            pulse.pulse = rank*segmentSize + pulseID
            pulse.SNR = snr[index]
            pulse.DM = DM
            pulse.time = index*tInt*ndown
            pulse.dtau = tInt*ndown
            pulse.dnu = channelWidth
            pulse.nu = centerFreq
            pulse.mean = mean
            pulse.rms = rms
            pulse.nu1 = bottomFreqBP
            pulse.nu2 = freqs[-1]
            outFile.Write_shared(pulse.__str__()[:]) 

            pulseID += 1
         # endfor
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
   main(sys.argv[1:])
   sys.exit(0)
# endif
