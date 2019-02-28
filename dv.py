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
   formatter = "{0.pulse:07d}    {0.SNR:10.6f}     {0.DM:10.4f}     {0.time:10.6f} " + \
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


main_radiotrans(args):
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
   cmdlnParser.add_option("-l", "--lower-fft-index", dest="lowerFFTIndex", default=0, action="store",
                           help="Lower FFT index of the bandpass to de-disperse.", metavar="INDEX")
   cmdlnParser.add_option("-u", "--upper-fft-index", dest="upperFFTIndex", default=4095, action="store",
                           help="Upper FFT index of the bandpass to de-disperse.", metavar="INDEX")
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
      else:
         centerFreq = commConfigObj.getfloat("Raw Data", "tuningfreq1")/10^6
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
   #
   # Load the combined spectrogram file.
   try:
      spectrogram = np.load(spectFilepath, mmap_mode='r')
   except:
      procMessage("dv.py: Could not open or load spectrogram file {file}".format(file=spectFilepath),
                  msg_type="ERROR")
   # endtry
   #
   # Open the output file in shared mode.
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
   freqs = apputils.computeFreqs(centerFreq, bandwidth, cmdlnOpts.lowerFFTIndex,
                                 cmdlnOpts.upperFFTIndex, DFTLength + 1) + channelWidth
   freqIndices = np.arange(len(freqs), dtype=np.int32)
   bottomFreqBP = freqs[0] - channelWidth # Bottom frequency in the bandpass.
   # Assign every rank-th frequency to current process to de-disperse.
   mask = (freqIndices % numProcs == rank)
   procFreqIndices = freqIndices[mask]
   # Rank 0 process picks up the remainder of frequencies.
   if rank == 0:
      lastIndex = procFreqIndices[-1]
      np.append(procFreqIndices, freqIndices[lastIndex:])
   # endif

   # CCY - figure this shit out.  What the hell is it doing, and why do we need it?
   maxPulseWidth = np.round( np.log2(cmdlnOpts.maxPulseWidth/tInt) ).astype(np.int32) + 1 
   txtsize=np.zeros((npws,2),dtype=np.int32) #fileno = txtsize[ranki,0], pulse number = txtsize[ranki,1],ranki is the decimated order of 2
   txtsize[:,0]=1 #fileno star from 1

   # Determine dispersion measure trials and scaled dispersion delays.
   DMtrials = []
   scaledDelays = []
   if rank == 0:
      numMidTrials = np.floor(cmdlnOpts.DMEnd) - np.ceil(cmdlnOpts.DMStart)
      DMtrials = np.zeros(numMidTrials + 2, dtype=np.float32)
      DMtrials[0] = cmdlnOpts.DMStart
      DMtrials[numMidTrials + 1] = cmdlnOpts.DMEnd
      DMtrials[1:numTrials + 1] = np.arange(numMidTrials, dtype=np.float32) + np.ceil(cmdlnOpts.DMStart)

      scaledDelays = apputils.scaleDelays(freqs)
   # endif
   DMtrials = MPIComm.bcast(DMtrials, root=0)
   scaledDelays = MPIComm.bcast(scaledDelays, root=0)

   # Allocate the de-dispersed time series. Yes, this is allocating the worst case, which results in
   # some wasted space, but it should run much faster without having to perform an allocation for each
   # DM trial.  Also, the time series occupy far, far less space than the spectrogram.
   tbMax = np.round(cmdlnOpts.DMEnd/tInt*scaledDelays[0]).astype(np.int32)
   ts = np.zeros(tbMax + spectrogram.shape[0], dtype=np.float32)
   tstotal = np.zeros(ts.shape[0], dtype=np.float32)

   # Perform de-dispersion search for pulses with temporal widths less than or equal to the specified 
   # pulse-width.
   for DM in DMtrials:
      # Compute array of dispersion delays as an index in units of tInt.
      tb=np.round(DM/tInt*scaledDelays).astype(np.int32)
      fShifts = tb[0] - tb
      # De-disperse the frequencies assigned to this process.
      for fIndex in procFreqIndices: 
         ts[fshifts[fIndex] : fshift[fIndex] + tsLength] += spectrogram[ : , fIndex]
      # endfor

      # Merge the de-dispersed time-series from all processes.
      MPIComm.Allreduce(ts, tstotal, op=MPI.SUM)
      # Cut the dispersed time lag.
      dedispTS = tstotal[tb[0] : ts.shape[0] - tb[0]]

      # Search for signal with decimated timeseries
      if rank < npws: # timeseries is ready for signal search
         ndown = 2**rank #decimate the time series
         (snr, mean, rms) = Threshold(apputils.DecimateNPY(tstotal,ndown), thresh, niter=0)
         pulseIndices = np.where(sn!=-1)[0]
         for index in pulseIndices:# Now record all pulses above threshold
            txtsize[ranki,1] += 1
            pulse.pulse = txtsize[ranki,1]
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

            if txtsize[ranki,1] >200000*txtsize[ranki,0]:
               outfile.close()
               txtsize[ranki,0]+=1
               filename = "ppc_SNR_pol_%.1i_td_%.2i_no_%.05d.txt" % (pol,ranki,txtsize[ranki,0])
               outfile = open(filename,'a')
            # endif
         # endfor
      # endif

      # Clear the summated time-series.
      tstotal.fill(0)
   # endfor

   outFile.Close()
# end main_radiotrans()


if __name__ == "__main__":
   main_radiotrans(sys.argv[1:])
# endif
