import sys
import numpy as np
import os
import time
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
   cmdlnParser.add_option('-o', '--outfilename', dest='outFilename', type='string', action='store',
                           help='Output filename.', metavar='NAME')
   cmdlnParser.add_option("-c", "--commconfig", dest="configFilepath", type="string",
                           default="./radiotrans.ini", action="store",
                           help="Path to the common parameters file.",
                           metavar="PATH")
   cmdlnParser.add_option('-t', '--high-tuning', dest='fHighTuning', default=False, action='store_true',
                           help='Flag denoting whether this is tuning 1 (enabled) or tuning 0.')

   (cmdlnOpts, cmdlnArgs) = cmdlnParser.parse_args(args)
   if not len(cmdlnArgs[0]) > 0:
      print 'Error (watchwaterfall.py): Must specify path to waterfall spectrogram file'
      sys.exit(1)
   # endif
   waterfall = np.load(cmdlnArgs[0])
   lowerIndex = forceIntValue(cmdlnOpts.lowerIndex, 0, 4095)
   upperIndex = forceIntValue(cmdlnOpts.upperIndex, 0, 4095)
   if not upperIndex > lowerIndex:
      print 'Error (watchwaterfall.py): Upper FFT index must be greater than lower FFT index'
      sys.exit(1)
   # endif

   bandpass = np.median(waterfall, 0).reshape((waterfall.shape[1],))
   baseline = np.median(waterfall, 1).reshape((waterfall.shape[0],))
   # CCY - NOTE: I don't know the reason for the particular choice in the parameters sent to
   # sativzky_golay.  I'm merely transcribing those parameters over.
   if cmdlnOpts.fHighTuning:
      bandpass = savitzky_golay(bandpass, 111, 2)
   else:
      bandpass = savitzky_golay(bandpass, 151, 2)
   # endif
   baseline = savitzky_golay(baseline, 151, 2)

   waterfall = waterfall - bandpass
   waterfall = (waterfall.T - baseline).T
   waterfall = RFI(waterfall, 5.0*waterfall.std())
   waterfall = snr(waterfall)
   noiseFloorSNR = waterfall.mean()
   mask = abs(waterfall) > 5.0*waterfall.std()
   waterfall[mask] = noiseFloorSNR

   plt.imshow(waterfall.T, cmap='Greys_r', origin = 'low', aspect = 'auto')
   plt.suptitle('Spectrogram {label}'.format(label=cmdlnOpts.label), fontsize = 30)
   plt.xlabel('Time (14 sec)',fontdict={'fontsize':16})
   plt.ylabel('Frequency (4.7 kHz)',fontdict={'fontsize':14})
   plt.colorbar().set_label('SNR',size=18)
   plt.savefig('{dir}/{name}'.format(dir=cmdlnOpts.workDir, name=cmdlnOpts.outFilename))
   plt.clf()
# end main()

if __name__ == "__main__":
   main(sys.argv[1:])
# endif
