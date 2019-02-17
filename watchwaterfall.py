import sys
import numpy as np
import os
import time
from ConfigParser import ConfigParser
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from optparse import OptionParser
from apputils import forceIntValue, savitzky_golay, RFI, snr



# Main routine
def main(args):
   usage = "Usage: %prog [options] <coarse_waterfall file>"
   cmdlnParser = OptionParser(usage=usage)
   cmdlnParser.add_option('-l', '--lower-FFT-index', dest='lowerIndex', default=0, type='int',
                           action='store', 
                           help='Lower FFT index cutoff (integer value between 0 and 4095)', 
                           metavar='INDEX')
   cmdlnParser.add_option('-u', '--upper-FFT-index', dest='upperIndex', default=0, type='int',
                           action='store', 
                           help='Upper FFT index cutoff (integer value between 0 and 4095)', 
                           metavar='INDEX')
   cmdlnParser.add_option('-w', '--work-dir', dest='workDir', default='.', type='string',
                           action='store', help='Working directory path', metavar='PATH')
   cmdlnParser.add_option('-b', '--label', dest='label', default='coarse', type='string',
                           action='store',
                           help='Label for the plot', metavar='LABEL')
   cmdlnParser.add_option('-o', '--outfile', dest='outFilepath', type='string', action='store',
                           help='Output filename.', metavar='NAME')
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_option('-t', '--high-tuning', dest='fHighTuning', default=False, action='store_true',
                           help='Flag denoting whether this is tuning 1 (enabled) or tuning 0.')
   cmdlnParser.add_option('-r', '--rfi-std-cutoff', dest='RFIStd', type='float', default=5.0,
                           action='store',
                           help='RFI standard deviation cut-off.', metavar='STD')
   cmdlnParser.add_option('-s', '--snr-cutoff', dest='SNRCutoff', type='float', default=3.0,
                           action='store',
                           help='SNR cut-off.', metavar='SNR')
   cmdlnParser.add_option('-g', '--savitzky-golay', dest='SGParams', default='151,2,151,2',
                           type='string', action='store',
                           help='Savitzky-Golay parameters for bandpass and baseline smoothing',
                           metavar='PARAMS')

   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)
   if not len(cmdlnArgs[0]) > 0:
      print 'Error (watchwaterfall.py): Must specify path to waterfall spectrogram file'
      sys.exit(1)
   # endif

   # Read common parameters file for need common parameters and update with the RFI std cutoff.
   try:
      commConfigObj = ConfigParser()
      # Read current common parameters.
      configFile = open(cmdlnOpts.configFilepath,"r")
      commConfigObj.readfp(configFile, cmdlnOpts.configFilepath)
      samplerate = commConfigObj.getfloat('Raw Data', 'samplerate')
      numSamplesPerFrame = commConfigObj.getint('Raw Data', 'numsamplesperframe')
      decimation = commConfigObj.getint('Reduced DFT Data', 'decimation')
      integTime = commConfigObj.getfloat('Reduced DFT Data', 'integrationtime')
      numSpectLines = commConfigObj.getint('Reduced DFT Data', 'numspectrogramlines')
      DFTLength = commConfigObj.getint('Reduced DFT Data', 'dftlength')
      configFile.close()

      # Update common parameters with RFI std cut-off and SNR ceiling cutoff.
      configFile = open(cmdlnOpts.configFilepath,"w")
      if not commConfigObj.has_section('RFI Bandpass'):
         commConfigObj.add_section('RFI Bandpass')
      # endif
      commConfigObj.set('RFI Bandpass', 'rfistdcutoff', cmdlnOpts.RFIStd)
      commConfigObj.set('RFI Bandpass', 'snrcutoff', cmdlnOpts.SNRCutoff)
      commConfigObj.write(configFile)
      configFile.close()
   except Exception as anError:
      print 'Could not read common parameters configuration file: ', cmdlnOpts.configFilepath
      print anError
      configFile.close()
      sys.exit(1)
   # endtry

   waterfall = np.load(cmdlnArgs[0])
   lowerIndex = forceIntValue(cmdlnOpts.lowerIndex, 0, DFTLength - 1)
   upperIndex = forceIntValue(cmdlnOpts.upperIndex, 0, DFTLength - 1)
   if not upperIndex > lowerIndex:
      print 'Error (watchwaterfall.py): Upper FFT index must be greater than lower FFT index'
      sys.exit(1)
   # endif

   # Parse Savitzky-Golay parameters.
   SGParams = [151, 2, 151, 2]
   cmdlnSGParams = cmdlnOpts.SGParams.split(',')
   numSGParams = len(cmdlnSGParams)
   if numSGParams > 3:
      SGParams[:4] = [int(x) for x in cmdlnSGParams[:4]]
   else:
      SGParams[:numSGParams] = [int(x) for x in cmdlnParams[:numSGParams]]
   # endif

   # CCY - NOTE: I don't know the reason for the particular choice in the parameters sent to
   # sativzky_golay.  I'm merely transcribing those parameters over.
   # Correct bandpass.
   bandpass = np.median(waterfall, 0).reshape((waterfall.shape[1],))
   bandpass = savitzky_golay(bandpass, SGParams[0], SGParams[1]).reshape((1,waterfall.shape[1]))
   waterfall = waterfall - bandpass

   # Correct baseline.
   baseline = np.median(waterfall, 1).reshape((waterfall.shape[0],))
   baseline = savitzky_golay(baseline, SGParams[2], SGParams[3]).reshape((waterfall.shape[0],1))
   waterfall = waterfall - baseline

   # Correct RFI.
   waterfall = RFI(waterfall, cmdlnOpts.RFIStd*waterfall.std())
   waterfall = snr(waterfall)
   mask = np.where( abs(waterfall) > cmdlnOpts.SNRCutoff*(waterfall[:,:].std()) )
   waterfall[:,:][mask] = waterfall[:,:].mean()

   freqStep = samplerate/(numSamplesPerFrame*1000.0)
   timeStep = integTime * int(numSpectLines/decimation)
   plt.imshow(waterfall.T, cmap='Greys_r', origin = 'low', aspect = 'auto')
   plt.suptitle('{label} RFI {std:.2f}$\sigma$'.format(label=cmdlnOpts.label,
                  std=cmdlnOpts.RFIStd), fontsize = 28)
   plt.xlabel('Time ({step:.4f} sec)'.format(step=timeStep),fontdict={'fontsize':16})
   plt.ylabel('Frequency ({step:.3f} kHz)'.format(step=freqStep),fontdict={'fontsize':16})
   plt.colorbar().set_label('SNR',size=16)
   plt.savefig(cmdlnOpts.outFilepath)
   plt.clf()
# end main()

if __name__ == "__main__":
   main(sys.argv[1:])
# endif
